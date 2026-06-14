#!/usr/bin/env cabal
{- cabal:
build-depends: base, directory, filepath, process, bytestring, dbus, time, unix
-}

-- A single binary with two roles:
--   * One-shot CLI:  `xmobar-status <widget>`  prints one widget string (the
--     legacy mode; kept as the daemon's fallback / for debugging).
--   * Resident daemon: `xmobar-status daemon` holds ONE persistent system-bus
--     connection, recomputes every widget on a coarse timer, and writes the
--     whole right-hand bar segment to a FIFO that xmobar reads via PipeReader.
--     This replaces ~730 process spawns/min (each mapping ~97 shared libs) and
--     ~280 D-Bus connect/disconnect cycles/min with one idle-ish process.
-- The daemon's own liveness is reported by the independent `statusd` widget,
-- which reads a heartbeat file (a dead daemon cannot report its own death).

module Main where

import Control.Concurrent (threadDelay)
import Control.Exception (try, SomeException)
import Control.Monad (when)
import Data.Char (isDigit, isSpace)
import Data.List (find, intercalate, isPrefixOf, isInfixOf)
import Data.Maybe (catMaybes)
import Data.Word (Word8, Word32)
import qualified Data.ByteString as BS
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import System.Directory (listDirectory, doesFileExist, doesDirectoryExist, removeFile, renameFile)
import System.Environment (getArgs, lookupEnv)
import System.FilePath ((</>))
import System.IO (openFile, IOMode(..), hGetContents', hClose)
import System.Process (readProcess)
import Data.Time.Clock.POSIX (getPOSIXTime)
import qualified DBus
import qualified DBus.Client as DBus

-- Theme colors with defaults
data Theme = Theme
  { tFg     :: String
  , tBg     :: String
  , tGood   :: String
  , tWarn   :: String
  , tErr    :: String
  , tAccent :: String
  , tDim    :: String
  , tMid    :: String
  , tFrost  :: String
  , tNormal :: String
  } deriving Show

defaultTheme :: Theme
defaultTheme = Theme
  { tFg     = "#FFFFFF"
  , tBg     = "#000000"
  , tGood   = "#B6E63E"
  , tWarn   = "#FFCC00"
  , tErr    = "#E74C3C"
  , tAccent = "#4CB5F5"
  , tDim    = "#525254"
  , tMid    = "#C0C5CF"
  , tFrost  = "#D0E1F9"
  , tNormal = "#D0E1F9"
  }

loadTheme :: IO Theme
loadTheme = do
  exists <- doesFileExist "/tmp/xmobar-theme"
  if not exists then return defaultTheme
  else do
    contents <- readFileSafe "/tmp/xmobar-theme"
    let pairs = [(k, stripQuotes v) | l <- lines contents
                                    , let (k, rest) = break (== '=') l
                                    , not (null rest)
                                    , let v = drop 1 rest]
        lk key def = maybe def id (lookup key pairs)
    return Theme
      { tFg     = lk "FG"     (tFg defaultTheme)
      , tBg     = lk "BG"     (tBg defaultTheme)
      , tGood   = lk "GOOD"   (tGood defaultTheme)
      , tWarn   = lk "WARN"   (tWarn defaultTheme)
      , tErr    = lk "ERR"    (tErr defaultTheme)
      , tAccent = lk "ACCENT" (tAccent defaultTheme)
      , tDim    = lk "DIM"    (tDim defaultTheme)
      , tMid    = lk "MID"    (tMid defaultTheme)
      , tFrost  = lk "FROST"  (tFrost defaultTheme)
      , tNormal = lk "NORMAL" (tNormal defaultTheme)
      }
  where
    stripQuotes ('"':s) = case reverse s of
      '"':r -> reverse r
      _     -> s
    stripQuotes s = s

-- Helpers

readFileSafe :: FilePath -> IO String
readFileSafe path = do
  result <- try go :: IO (Either SomeException String)
  return $ either (const "") id result
  where
    go = do
      h <- openFile path ReadMode
      s <- hGetContents' h
      hClose h
      return s

writeFileSafe :: FilePath -> String -> IO ()
writeFileSafe path s = do
  _ <- try (writeFile path s) :: IO (Either SomeException ())
  return ()

trim :: String -> String
trim = f . f where f = reverse . dropWhile isSpace

fn1 :: String -> String
fn1 s = "<fn=1>" ++ s ++ "</fn>"

fn4 :: String -> String
fn4 s = "<fn=4>" ++ s ++ "</fn>"

fc :: String -> String -> String
fc color s = "<fc=" ++ color ++ ">" ++ s ++ "</fc>"

icon :: String -> String -> String
icon color glyph = fn1 (fc color glyph)

iconSmall :: String -> String -> String
iconSmall color glyph = fn4 (fc color glyph)

fn5 :: String -> String
fn5 s = "<fn=5>" ++ s ++ "</fn>"

iconXs :: String -> String -> String
iconXs color glyph = fn5 (fc color glyph)

readInt :: String -> Int
readInt s = case reads (trim s) of
  [(n, _)] -> n
  _        -> 0

readIntegerSafe :: String -> Integer
readIntegerSafe s = case reads (trim s) of
  [(n, _)] -> n
  _        -> 0

-- Transient critical-state alert.
-- Returns a "!" string the first time `critical` flips true and for
-- `alertWindowSec` seconds after, alternating bold (fn=3) with normal
-- weight at 2 Hz so it visibly pulses. After the window the alert is
-- silent until `critical` clears and re-asserts.
-- The daemon ticks coarsely, so during an alert the pulse animates at the
-- tick rate; that is acceptable for a transient warning.
alertWindowSec :: Double
alertWindowSec = 8.0

alertSymbol :: Theme -> String -> Bool -> IO String
alertSymbol t name critical = do
  let stateFile = "/tmp/xmobar-alert-" ++ name
  if not critical
    then do
      _ <- try (removeFile stateFile) :: IO (Either SomeException ())
      return ""
    else do
      now <- realToFrac <$> getPOSIXTime :: IO Double
      contents <- readFileSafe stateFile
      start <- case reads contents :: [(Double, String)] of
        [(s, _)] -> return s
        _        -> writeFile stateFile (show now) >> return now
      if now - start > alertWindowSec
        then return ""
        else do
          let bucket = floor (now * 2) :: Int
              wrap s = if even bucket then "<fn=3>" ++ s ++ "</fn>" else s
          return $ " " ++ fc (tErr t) (wrap "!")

findHwmon :: [String] -> IO (Maybe FilePath)
findHwmon names = do
  exists <- doesDirectoryExist "/sys/class/hwmon"
  if not exists then return Nothing
  else do
    entries <- listDirectory "/sys/class/hwmon"
    go entries
  where
    go [] = return Nothing
    go (e:es) = do
      let nameFile = "/sys/class/hwmon" </> e </> "name"
      name <- trim <$> readFileSafe nameFile
      if name `elem` names
        then return (Just ("/sys/class/hwmon" </> e))
        else go es

findFirst :: FilePath -> String -> IO (Maybe FilePath)
findFirst dir pattern = do
  exists <- doesDirectoryExist dir
  if not exists then return Nothing
  else do
    entries <- listDirectory dir
    case find (isPrefixOf pattern) entries of
      Just e  -> return (Just (dir </> e))
      Nothing -> return Nothing

cachedLookup :: FilePath -> IO (Maybe FilePath) -> IO (Maybe FilePath)
cachedLookup cacheFile discover = do
  exists <- doesFileExist cacheFile
  if exists
    then Just . trim <$> readFileSafe cacheFile
    else do
      result <- discover
      case result of
        Just path -> writeFile cacheFile path >> return (Just path)
        Nothing   -> return Nothing

-- Runtime paths (output file, heartbeat, web2org state) live under
-- $XDG_RUNTIME_DIR (tmpfs, cleared on logout); fall back to /tmp if unset.
-- The daemon writes its rendered bar segment to a regular file that every
-- xmobar instance reads with `cat` — a file broadcasts to N readers, so this
-- is multi-monitor-safe (a single FIFO would split bytes between bars).

runtimeDir :: IO FilePath
runtimeDir = maybe "/tmp" id <$> lookupEnv "XDG_RUNTIME_DIR"

outPath :: IO FilePath
outPath = (</> "xmobar-statusd.out") <$> runtimeDir

beatPath :: IO FilePath
beatPath = (</> "xmobar-statusd.beat") <$> runtimeDir

w2oDir :: IO FilePath
w2oDir = (</> "web2org") <$> runtimeDir

-- UPower (battery via D-Bus). Avoids vendor-specific sysfs differences
-- (e.g. ThinkPad exposes power_now, Framework exposes current_now).
-- Takes the client so the daemon can reuse ONE persistent connection
-- (and so battery+power share a single query rather than two connects).

data UPowerInfo = UPowerInfo
  { upPercent :: Int       -- 0..100
  , upState   :: Word32    -- 0=Unknown 1=Charging 2=Discharging 3=Empty 4=Full ...
  , upWatts   :: Double    -- positive (always magnitude)
  } deriving Show

queryUPower :: DBus.Client -> IO (Maybe UPowerInfo)
queryUPower client = do
  result <- try go :: IO (Either SomeException (Maybe UPowerInfo))
  return $ either (const Nothing) id result
  where
    go = do
      reply  <- DBus.call_ client (DBus.methodCall
                  (DBus.objectPath_ "/org/freedesktop/UPower")
                  (DBus.interfaceName_ "org.freedesktop.UPower")
                  (DBus.memberName_ "EnumerateDevices"))
                  { DBus.methodCallDestination = Just (DBus.busName_ "org.freedesktop.UPower") }
      let paths = case DBus.methodReturnBody reply of
                    [v] -> maybe [] id (DBus.fromVariant v :: Maybe [DBus.ObjectPath])
                    _   -> []
      let isBat p = "battery_" `isInfixOf` DBus.formatObjectPath p
      case filter isBat paths of
        []      -> return Nothing
        (bp:_)  -> Just <$> readBatteryProps bp

    readBatteryProps objPath = do
      let getProp prop = do
            r <- DBus.call_ client (DBus.methodCall
                    objPath
                    (DBus.interfaceName_ "org.freedesktop.DBus.Properties")
                    (DBus.memberName_ "Get"))
                    { DBus.methodCallDestination = Just (DBus.busName_ "org.freedesktop.UPower")
                    , DBus.methodCallBody =
                        [ DBus.toVariant ("org.freedesktop.UPower.Device" :: String)
                        , DBus.toVariant (prop :: String) ] }
            return $ case DBus.methodReturnBody r of
                       [v] -> DBus.fromVariant v :: Maybe DBus.Variant
                       _   -> Nothing
      mPct   <- getProp "Percentage"
      mState <- getProp "State"
      mRate  <- getProp "EnergyRate"
      let pct  = maybe 0   id (mPct   >>= DBus.fromVariant :: Maybe Double)
          st   = maybe 0   id (mState >>= DBus.fromVariant :: Maybe Word32)
          rate = maybe 0.0 id (mRate  >>= DBus.fromVariant :: Maybe Double)
      return $ UPowerInfo (round pct) st (abs rate)

-- NetworkManager (wifi via D-Bus). Handles iw/iwd/wpa_supplicant uniformly.

data NMWifi = NMWifi
  { nmIface    :: String     -- "wlan0"
  , nmSsid     :: String
  , nmStrength :: Word8      -- 0..100
  } deriving Show

nmName :: DBus.BusName
nmName = DBus.busName_ "org.freedesktop.NetworkManager"

nmRoot :: DBus.ObjectPath
nmRoot = DBus.objectPath_ "/org/freedesktop/NetworkManager"

nmGetProp :: DBus.Client -> DBus.ObjectPath -> String -> String -> IO (Maybe DBus.Variant)
nmGetProp client objPath iface prop = do
  r <- DBus.call_ client (DBus.methodCall objPath
                          (DBus.interfaceName_ "org.freedesktop.DBus.Properties")
                          (DBus.memberName_ "Get"))
          { DBus.methodCallDestination = Just nmName
          , DBus.methodCallBody =
              [ DBus.toVariant (iface :: String)
              , DBus.toVariant (prop :: String) ] }
  return $ case DBus.methodReturnBody r of
             [v] -> DBus.fromVariant v :: Maybe DBus.Variant
             _   -> Nothing

queryNMWifi :: DBus.Client -> IO (Maybe NMWifi)
queryNMWifi client = do
  result <- try go :: IO (Either SomeException (Maybe NMWifi))
  return $ either (const Nothing) id result
  where
    go = do
      reply  <- DBus.call_ client (DBus.methodCall nmRoot
                  (DBus.interfaceName_ "org.freedesktop.NetworkManager")
                  (DBus.memberName_ "GetDevices"))
                  { DBus.methodCallDestination = Just nmName }
      let devs = case DBus.methodReturnBody reply of
                   [v] -> maybe [] id (DBus.fromVariant v :: Maybe [DBus.ObjectPath])
                   _   -> []
      findActiveWifi devs

    findActiveWifi [] = return Nothing
    findActiveWifi (dp:rest) = do
      mdt <- nmGetProp client dp "org.freedesktop.NetworkManager.Device" "DeviceType"
      let dtype = maybe 0 id (mdt >>= DBus.fromVariant :: Maybe Word32)
      if dtype /= 2     -- 2 = NM_DEVICE_TYPE_WIFI
        then findActiveWifi rest
        else do
          mIfV <- nmGetProp client dp "org.freedesktop.NetworkManager.Device" "Interface"
          let iface = maybe "" id (mIfV >>= DBus.fromVariant :: Maybe String)
          mApV <- nmGetProp client dp "org.freedesktop.NetworkManager.Device.Wireless" "ActiveAccessPoint"
          case mApV >>= DBus.fromVariant :: Maybe DBus.ObjectPath of
            Nothing                                   -> return Nothing
            Just ap | DBus.formatObjectPath ap == "/" -> return Nothing
            Just ap -> do
              mSsid <- nmGetProp client ap "org.freedesktop.NetworkManager.AccessPoint" "Ssid"
              mStr  <- nmGetProp client ap "org.freedesktop.NetworkManager.AccessPoint" "Strength"
              -- NM returns the SSID as a raw UTF-8 byte array; decode it as
              -- UTF-8 (not Latin-1, which would mojibake non-ASCII chars like
              -- the U+2019 apostrophe in "Dmitry's iPhone").
              let ssid = maybe "" (T.unpack . TE.decodeUtf8Lenient) (mSsid >>= DBus.fromVariant :: Maybe BS.ByteString)
                  strg = maybe 0  id          (mStr  >>= DBus.fromVariant :: Maybe Word8)
              return $ Just (NMWifi iface ssid strg)

-- NetworkManager active VPN/WireGuard connection lookup.

queryNMVpn :: DBus.Client -> IO (Maybe String)
queryNMVpn client = do
  result <- try go :: IO (Either SomeException (Maybe String))
  return $ either (const Nothing) id result
  where
    go = do
      mActive <- nmGetProp client nmRoot
                   "org.freedesktop.NetworkManager" "ActiveConnections"
      let acs = maybe [] id (mActive >>= DBus.fromVariant :: Maybe [DBus.ObjectPath])
      findVpn acs

    findVpn [] = return Nothing
    findVpn (ap:rest) = do
      mTy <- nmGetProp client ap "org.freedesktop.NetworkManager.Connection.Active" "Type"
      let ty = maybe "" id (mTy >>= DBus.fromVariant :: Maybe String)
      if ty == "wireguard" || ty == "vpn"
        then do
          mId <- nmGetProp client ap "org.freedesktop.NetworkManager.Connection.Active" "Id"
          let cid = maybe "" id (mId >>= DBus.fromVariant :: Maybe String)
          return (Just cid)
        else findVpn rest

-- Widgets: each returns its xmobar-markup string (the daemon concatenates them;
-- the CLI prints one). D-Bus widgets are split into query (takes a client) and
-- render (pure-ish) so the daemon can query UPower once for battery+power.

renderBattery :: Theme -> Maybe UPowerInfo -> IO String
renderBattery t mInfo = case mInfo of
  Nothing -> return ""
  Just (UPowerInfo cap st _) -> do
      let ico = case st of
                  1 -> "\xF0E7"               -- nf-fa-bolt (charging)
                  2 | cap <= 12  -> "\xF244"  -- nf-fa-battery_empty
                    | cap <= 37  -> "\xF243"  -- nf-fa-battery_quarter
                    | cap <= 62  -> "\xF242"  -- nf-fa-battery_half
                    | cap <= 87  -> "\xF241"  -- nf-fa-battery_three_quarters
                    | otherwise  -> "\xF240"  -- nf-fa-battery_full
                  _ -> "\xF240"               -- nf-fa-battery_full
          color | cap <= 20 = tErr t
                | cap <= 80 = tWarn t
                | otherwise = tGood t
      alert <- alertSymbol t "battery" (cap <= 20)
      let icoFn = if st == 1 then iconXs else iconSmall
      return $ icoFn (tFg t) ico ++ " " ++ fc color (show cap) ++ "%" ++ alert

renderPower :: Theme -> Maybe UPowerInfo -> IO String
renderPower t mInfo = case mInfo of
  Just (UPowerInfo _ st watts) | watts > 0 -> do
      let w10  = round (watts * 10) :: Int
          wInt = w10 `div` 10
          wDec = w10 `mod` 10
          color | wInt < 15 = tGood t
                | wInt < 25 = tWarn t
                | otherwise = tErr t
      alert <- alertSymbol t "power" (st == 2 && wInt >= 25)
      -- State: 0=Unknown 1=Charging 2=Discharging 3=Empty 4=Full 5=PendingCharge 6=PendingDischarge
      case st of
        2 -> return $ "-" ++ fc color (show wInt ++ "." ++ show wDec) ++ "W" ++ alert
        _ -> return $ "+" ++ fc (tGood t) (show wInt ++ "." ++ show wDec) ++ "W"
  _ -> return ""

brightness :: Theme -> IO String
brightness t = do
  mbl <- cachedLookup "/tmp/xmobar-backlight" $
    findFirst "/sys/class/backlight" ""
  case mbl of
    Nothing -> return ""
    Just bl -> do
      cur <- readInt <$> readFileSafe (bl </> "brightness")
      mx  <- readInt <$> readFileSafe (bl </> "max_brightness")
      let pct = if mx > 0 then cur * 100 `div` mx else 0
          color | pct < 25  = tDim t
                | pct < 50  = tMid t
                | pct < 75  = tFrost t
                | otherwise = tWarn t
      return $ icon color "\xF0EB" ++ " " ++ show pct ++ "%"

cputemp :: Theme -> IO String
cputemp t = do
  mhw <- cachedLookup "/tmp/xmobar-cputemp-hwmon" $
    findHwmon ["coretemp", "k10temp"]
  case mhw of
    Nothing -> return ""
    Just hw -> do
      tempS <- readFileSafe (hw </> "temp1_input")
      let temp = readInt tempS `div` 1000
          color | temp <  50 = tGood t
                | temp <  70 = tNormal t
                | temp <  85 = tWarn t
                | otherwise  = tErr t
      alert <- alertSymbol t "cputemp" (temp >= 85)
      return $ fc color (show temp) ++ "\x00B0" ++ "C" ++ alert

volume :: Theme -> IO String
volume t = do
  result <- try (readProcess "wpctl" ["get-volume", "@DEFAULT_AUDIO_SINK@"] "")
            :: IO (Either SomeException String)
  case result of
    Left _    -> return "N/A"
    Right out -> do
      let ws = words out
          vol = case drop 1 ws of
                  (v:_) -> show (round (read v * 100 :: Double) :: Int) ++ "%"
                  _     -> "N/A"
          muted = "MUTED" `elem` ws
      return $ if muted then fc (tErr t) "[M]" else vol

-- Wi-Fi throughput needs the real sample interval (seconds since the previous
-- read of the rx/tx counters). The daemon passes its tick interval; this fixes
-- the old hard-coded dt=30 that made throughput read ~10x too low at a 3s poll.
renderWifi :: Theme -> Int -> Maybe NMWifi -> IO String
renderWifi t dt mw = case mw of
  Nothing -> return $ icon (tDim t) "\xF1EB" ++ " " ++ fc (tDim t) "disconnected"
  Just (NMWifi iface ssid strength) -> do
      let stateFile = "/tmp/wifi-status-" ++ iface
      rx <- readInt <$> readFileSafe ("/sys/class/net/" ++ iface ++ "/statistics/rx_bytes")
      tx <- readInt <$> readFileSafe ("/sys/class/net/" ++ iface ++ "/statistics/tx_bytes")
      prev <- readFileSafe stateFile
      let dt' = max 1 dt
          (rxR, txR) = case words prev of
            [prS, ptS] -> let pr = readInt prS
                              pt = readInt ptS
                          in ((rx - pr) `div` dt', (tx - pt) `div` dt')
            _          -> (0, 0)
          str       = fromIntegral strength :: Int
          strIcon = "\xF1EB"  -- nf-fa-wifi
          strColor  | str >= 50 = tGood t
                    | str >= 25 = tWarn t
                    | otherwise = tErr t
      now <- realToFrac <$> getPOSIXTime :: IO Double
      rxBurst <- checkBurst "rx" rxR now
      txBurst <- checkBurst "tx" txR now
      let rxColor | rxBurst   = tAccent t
                  | rxR > 1000 = tFg t
                  | otherwise  = tMid t
          txColor | txBurst   = tGood t
                  | txR > 1000 = tFg t
                  | otherwise  = tMid t
          rateStr =
            let (rxVal, rxUnit) = humanRate rxR
                (txVal, txUnit) = humanRate txR
            in "  " ++ fc rxColor ("\xF063 " ++ rxVal) ++ rxUnit ++
               "  " ++ fc txColor ("\xF062 " ++ txVal) ++ txUnit
      writeFile stateFile (show rx ++ " " ++ show tx)
      return $ icon strColor strIcon ++ " "
            ++ ssid
            ++ " " ++ fc strColor (show str) ++ "%"
            ++ rateStr
  where
    burstThreshold = 512000  -- 500KB/s
    burstWindowSec = 10.0
    checkBurst :: String -> Int -> Double -> IO Bool
    checkBurst dir rate now = do
      let sf = "/tmp/xmobar-burst-" ++ dir
      if rate > burstThreshold
        then do
          contents <- readFileSafe sf
          case reads contents :: [(Double, String)] of
            [(s, _)] -> return (now - s <= burstWindowSec)
            _        -> writeFile sf (show now) >> return True
        else do
          _ <- try (removeFile ("/tmp/xmobar-burst-" ++ dir)) :: IO (Either SomeException ())
          return False
    humanRate :: Int -> (String, String)
    humanRate n
      | n >= 1048576 = let m10 = (n * 10) `div` 1048576
                       in (show (m10 `div` 10) ++ "." ++ show (m10 `mod` 10), "M/s")
      | n >= 1024    = (show (n `div` 1024), "K/s")
      | otherwise    = (show n, "B/s")

renderVpn :: Theme -> Maybe String -> IO String
renderVpn t mName = case mName of
  Nothing   -> return $ iconXs (tDim  t) "\xF09C" ++ " " ++ fc (tDim  t) "off"
  Just name -> return $ iconXs (tGood t) "\xF023" ++ " " ++ fc (tGood t) name

emacs :: Theme -> IO String
emacs t = do
  status <- trim <$> readFileSafe "/tmp/emacs-status"
  let color = case status of
        "ready"    -> tGood t
        "starting" -> tWarn t
        "error"    -> tErr t
        _          -> tDim t
  return $ icon color "\xE632"

gpu :: Theme -> IO String
gpu t = do
  let cacheFile = "/tmp/gpu-cards"
  exists <- doesFileExist cacheFile
  if not exists
    then do
      exists' <- doesDirectoryExist "/sys/class/drm"
      if not exists'
        then return ""
        else do
          entries <- listDirectory "/sys/class/drm"
          let cards = filter (\e -> "card" `isPrefixOf` e && all (`elem` "0123456789") (drop 4 e)) entries
          foundAny <- buildGpuCache cacheFile cards
          if not foundAny then return "" else gpuOutput t cacheFile
    else gpuOutput t cacheFile

buildGpuCache :: FilePath -> [String] -> IO Bool
buildGpuCache cacheFile cards = go cards False
  where
    go [] found = return found
    go (card:rest) found = do
      let gpuFile = "/sys/class/drm" </> card </> "device" </> "gpu_busy_percent"
      hasGpu <- doesFileExist gpuFile
      if not hasGpu then go rest found
      else do
        let bootVgaFile = "/sys/class/drm" </> card </> "device" </> "boot_vga"
        bootVga <- trim <$> readFileSafe bootVgaFile
        -- boot_vga=1 → primary/integrated GPU; 0 (or missing) → discrete
        let label = if bootVga == "1" then "iGPU" else "dGPU"
        appendFile cacheFile (card ++ " " ++ label ++ "\n")
        go rest True

gpuOutput :: Theme -> FilePath -> IO String
gpuOutput t cacheFile = do
  contents <- readFileSafe cacheFile
  parts <- mapM (formatGpuCard t) (filter (not . null) (lines contents))
  let nonEmpty = filter (not . null) parts
  if null nonEmpty then return ""
  else return $ icon (tNormal t) "\xF26C" ++ " " ++ intercalate "  " nonEmpty ++ " | "

formatGpuCard :: Theme -> String -> IO String
formatGpuCard t line = case words line of
  (name:rest) -> do
    let label = unwords rest
        sys = "/sys/class/drm" </> name </> "device"
    exists <- doesDirectoryExist sys
    if not exists
      then return $ fc (tDim t) (label ++ " removed")
      else do
        state <- trim <$> readFileSafe (sys </> "power" </> "runtime_status")
        if state == "active"
          then do
            pct <- trim <$> readFileSafe (sys </> "gpu_busy_percent")
            let p = if null pct then "?" else pct
            return $ label ++ " " ++ p ++ "%"
          else return $ fc (tDim t) (label ++ " off")
  _ -> return ""

-- ACPI platform power profile (the lever toggled by M-S-p). Icon-only:
-- leaf = low-power, scale = balanced, bolt = performance.
powerprofile :: Theme -> IO String
powerprofile t = do
  p <- trim <$> readFileSafe "/sys/firmware/acpi/platform_profile"
  let (glyph, color) = case p of
        "low-power"   -> ("\xF06C", tGood t)    -- nf-fa-leaf
        "quiet"       -> ("\xF06C", tGood t)
        "cool"        -> ("\xF06C", tGood t)
        "balanced"    -> ("\xF24E", tAccent t)  -- nf-fa-balance_scale
        "performance" -> ("\xF0E7", tErr t)     -- nf-fa-bolt
        _             -> ("\xF013", tMid t)     -- nf-fa-cog (unknown)
  return $ if null p then "" else icon color glyph

disk :: Theme -> IO String
disk t = do
  result <- try (readProcess "df" ["-h", "/"] "") :: IO (Either SomeException String)
  let df = either (const "") id result
      raw = case lines df of
              (_:row:_) -> case words row of
                             (_:_:_:avail:_) -> avail
                             _ -> "?"
              _ -> "?"
      (num, unit) = span (\c -> c == '.' || isDigit c) raw
      gb = case reads num of
             [(n, _)] -> case unit of
               "T" -> n * 1024 :: Double
               "G" -> n
               "M" -> n / 1024
               _   -> n
             _ -> 0
      color | gb < 10   = tErr t
            | gb < 50   = tWarn t
            | otherwise = tGood t
  return $ fc color num ++ unit

tray :: Theme -> IO String
tray t = do
  let apps = [ ("slack",    "\xF198",  "#4A154B")  -- nf-fa-slack, Slack purple
             , ("telegram", "\xF2C6",  "#26A5E4")  -- nf-fa-telegram, Telegram blue
             ]
  running <- mapM (checkApp t) apps
  return $ unwords (filter (not . null) running)
  where
    checkApp _ (procName, ico, brandColor) = do
      result <- try (readProcess "pgrep" ["-x", procName] "") :: IO (Either SomeException String)
      case result of
        Right s | not (null (trim s)) -> return $ icon brandColor ico
        _ -> return ""

camera :: Theme -> IO String
camera t = do
  modules <- readFileSafe "/proc/modules"
  let loaded = any (isPrefixOf "uvcvideo") (lines modules)
      ico    = if loaded then "\xF030" else "\xF05E"
      color  = if loaded then tGood t   else tErr t
  return $ icon color ico

-- Count physically connected displays from DRM connector status in sysfs
-- (the electrical truth — xrandr/Xinerama can lag after an unplug if nothing
-- reconfigured the CRTCs). Connector dirs look like card2-eDP-2 / card2-DP-4
-- and each has a `status` file of connected/disconnected/unknown.
countConnectedDisplays :: IO Int
countConnectedDisplays = do
  ex <- doesDirectoryExist "/sys/class/drm"
  if not ex then return 0
  else do
    entries <- listDirectory "/sys/class/drm"
    sts <- mapM readStatus [e | e <- entries, '-' `elem` e]
    return (length (filter (== "connected") sts))
  where
    readStatus e = trim <$> readFileSafe ("/sys/class/drm" </> e </> "status")

-- Multi-display indicator: shown ONLY when more than one display is connected.
displays :: Theme -> IO String
displays t = do
  n <- countConnectedDisplays
  return $ if n > 1
             then icon (tAccent t) "\xF108" ++ " " ++ fc (tAccent t) (show n)  -- nf-fa-desktop
             else ""

-- CPU% from /proc/stat deltas (daemon keeps the previous sample). Mirrors the
-- former xmobar Cpu builtin (-L 3 -H 50, normal=GOOD, high=ERR).
cpuSample :: IO (Integer, Integer)   -- (total jiffies, idle jiffies)
cpuSample = do
  s <- readFileSafe "/proc/stat"
  case lines s of
    (l:_) -> case words l of
      ("cpu":fs) -> let ns    = map readIntegerSafe fs
                        total = sum ns
                        idle  = sum (take 2 (drop 3 ns))  -- idle + iowait
                    in return (total, idle)
      _ -> return (0, 0)
    _ -> return (0, 0)

renderCpu :: Theme -> (Integer, Integer) -> (Integer, Integer) -> String
renderCpu t (pt, pidle) (ct, cidle) =
  let dtot  = ct - pt
      didle = cidle - pidle
      pct   = if dtot <= 0 then 0 else fromIntegral ((dtot - didle) * 100 `div` dtot) :: Int
      color | pct > 50  = tErr t
            | pct > 3   = tGood t
            | otherwise = tFg t
  in fc color (show pct ++ "%")

-- Memory used-ratio from /proc/meminfo. Mirrors the former Memory builtin
-- (-L 50 -H 80, low=GOOD, normal=WARN, high=ERR).
memPct :: IO Int
memPct = do
  s <- readFileSafe "/proc/meminfo"
  let field key = case [ ws | l <- lines s, let ws = words l
                            , not (null ws), head ws == (key ++ ":") ] of
                    ((_:v:_):_) -> readIntegerSafe v
                    _           -> 0
      total = field "MemTotal"
      avail = field "MemAvailable"
  return $ if total > 0 then fromIntegral ((total - avail) * 100 `div` total) else 0

renderMem :: Theme -> Int -> String
renderMem t pct =
  let color | pct >= 80 = tErr t
            | pct >= 50 = tWarn t
            | otherwise = tGood t
  in fc color (show pct ++ "%")

-- Daemon liveness watchdog. Computed OUTSIDE the daemon (a dead daemon cannot
-- report its own death): reads the heartbeat file the daemon stamps each tick
-- and shows a green heart while fresh, red once stale/absent.
statusdHealth :: Theme -> IO String
statusdHealth t = do
  bp <- beatPath
  contents <- readFileSafe bp
  now <- realToFrac <$> getPOSIXTime :: IO Double
  let heart = "\xF21E"   -- nf-fa-heartbeat
      fresh = case reads contents :: [(Double, String)] of
                [(b, _)] -> now - b >= 0 && now - b < 8
                _        -> False
  return $ icon (if fresh then tGood t else tErr t) heart

-- web2org capture activity. web2org.sh maintains a state dir:
--   running/<pid>  : one marker file per in-flight capture
--   success        : one line appended per successful capture
--   failed         : one line appended per failed capture
-- (under $XDG_RUNTIME_DIR/web2org, tmpfs → resets on logout/reboot.)
web2orgWidget :: Theme -> IO String
web2orgWidget t = do
  dir <- w2oDir
  ip <- countRunning (dir </> "running")
  ok <- countLines (dir </> "success")
  fl <- countLines (dir </> "failed")
  let dl = "\xF0ED"  -- nf-fa-cloud_download
      baseColor | ip > 0    = tAccent t
                | fl > 0    = tErr t
                | ok > 0    = tGood t
                | otherwise = tDim t
      parts = catMaybes
        [ if ip > 0 then Just (fc (tAccent t) (fn1 "\xF021" ++ " " ++ show ip)) else Nothing  -- nf-fa-refresh
        , if ok > 0 then Just (fc (tGood t)   (fn1 "\xF00C" ++ " " ++ show ok)) else Nothing  -- nf-fa-check
        , if fl > 0 then Just (fc (tErr t)    (fn1 "\xF00D" ++ " " ++ show fl)) else Nothing  -- nf-fa-times
        ]
  return $ if null parts
             then icon baseColor dl
             else icon baseColor dl ++ " " ++ unwords parts
  where
    -- Each marker is named by the capturing pid. Count only live pids and
    -- sweep markers whose process is gone (a SIGKILL bypasses web2org's trap).
    countRunning d = do
      ex <- doesDirectoryExist d
      if not ex then return 0
      else do
        entries <- listDirectory d
        alives <- mapM (liveOrSweep d) entries
        return (length (filter id alives))
    liveOrSweep d pid = do
      live <- doesDirectoryExist ("/proc" </> pid)
      when (not live) $ do
        _ <- try (removeFile (d </> pid)) :: IO (Either SomeException ())
        return ()
      return live
    countLines f = length . filter (== '\n') <$> readFileSafe f

-- Assemble the whole right-hand bar segment, reproducing the original
-- template's literal separators/icons (vol=U+F028, cpu=U+F2DB, mem=U+F1C0,
-- disk=U+F0A0). kbd and date stay xmobar builtins (outside this string).
assembleLine :: WidgetStrings -> String
assembleLine w = concat
  [ unwords (filter (not . null) [wTray w, wW2o w, wDisplays w]), " | "
  , wCam w, " | "
  , wEmacs w, " | "
  , wBright w, " | "
  , "<fn=1>\xF028</fn> ", wVol w, " | "
  , wWifi w, " | "
  , wVpn w, " | "
  , wGpu w, " <fn=1>\xF2DB</fn> ", wCpu w, " ", wCputemp w, " | "
  , "<fn=4>\xF1C0</fn> ", wMem w, " | "
  , "<fn=1>\xF0A0</fn> ", wDisk w, " | "
  , wPprofile w, " ", wBat w, " ", wPow w
  ]

data WidgetStrings = WidgetStrings
  { wTray :: String, wW2o :: String, wDisplays :: String, wCam :: String
  , wEmacs :: String, wBright :: String, wVol :: String, wWifi :: String
  , wVpn :: String, wGpu :: String, wCpu :: String, wCputemp :: String
  , wMem :: String, wDisk :: String, wPprofile :: String, wBat :: String
  , wPow :: String
  }

-- Daemon: one persistent system-bus connection, coarse timer, dedup writes.
data DState = DState
  { dsClient :: Maybe DBus.Client
  , dsCpu    :: (Integer, Integer)
  , dsLine   :: String
  , dsTick   :: Int
  , dsDisk   :: String
  , dsTray   :: String
  }

-- Atomic publish: write to a temp file then rename over the target, so a
-- reader's `cat` never sees a half-written line.
atomicWrite :: FilePath -> String -> IO ()
atomicWrite path s = do
  _ <- try (writeFile (path ++ ".tmp") s >> renameFile (path ++ ".tmp") path)
         :: IO (Either SomeException ())
  return ()

ensureClient :: Maybe DBus.Client -> IO (Maybe DBus.Client)
ensureClient (Just c) = return (Just c)
ensureClient Nothing  =
  either (const Nothing) Just <$> (try DBus.connectSystem :: IO (Either SomeException DBus.Client))

runDaemon :: IO ()
runDaemon = do
  op <- outPath
  bp <- beatPath
  ms <- intervalMs
  let dtSec = max 1 (ms `div` 1000)
  cpu0 <- cpuSample
  loop op bp ms dtSec (DState Nothing cpu0 "" 0 "" "")
  where
    intervalMs = do
      mv <- lookupEnv "XMOBAR_STATUSD_INTERVAL_MS"
      return $ case mv >>= (\s -> case reads s of [(n, _)] -> Just n; _ -> Nothing) of
                 Just n | n >= 200 -> n
                 _                  -> 2000
    loop op bp ms dtSec st = do
      client <- ensureClient (dsClient st)
      t <- loadTheme
      (up, wf, vp) <- case client of
        Nothing -> return (Nothing, Nothing, Nothing)
        Just c  -> do
          u <- queryUPower c
          w <- queryNMWifi c
          v <- queryNMVpn c
          return (u, w, v)
      curCpu  <- cpuSample
      memS    <- renderMem t <$> memPct
      brightS <- brightness t
      ctS     <- cputemp t
      volS    <- volume t
      gpuS    <- gpu t
      camS    <- camera t
      emacsS  <- emacs t
      ppS     <- powerprofile t
      w2oS    <- web2orgWidget t
      dispS   <- displays t
      batS    <- renderBattery t up
      powS    <- renderPower t up
      wifiS   <- renderWifi t dtSec wf
      vpnS    <- renderVpn t vp
      -- Cadence the widgets that fork children (df, pgrep): disk rarely
      -- changes (~every 60s), tray every ~10s; reuse the cached string between.
      let tick = dsTick st
      diskS <- if tick `mod` 30 == 0 || null (dsDisk st) then disk t else return (dsDisk st)
      trayS <- if tick `mod` 5  == 0                     then tray t else return (dsTray st)
      let cpuS = renderCpu t (dsCpu st) curCpu
          line = assembleLine WidgetStrings
            { wTray = trayS, wW2o = w2oS, wDisplays = dispS, wCam = camS
            , wEmacs = emacsS, wBright = brightS, wVol = volS, wWifi = wifiS
            , wVpn = vpnS, wGpu = gpuS, wCpu = cpuS, wCputemp = ctS
            , wMem = memS, wDisk = diskS, wPprofile = ppS, wBat = batS
            , wPow = powS }
      now <- realToFrac <$> getPOSIXTime :: IO Double
      writeFileSafe bp (show now)
      when (line /= dsLine st) $ atomicWrite op line
      threadDelay (ms * 1000)
      loop op bp ms dtSec st { dsClient = client, dsCpu = curCpu
                             , dsLine = line, dsTick = tick + 1
                             , dsDisk = diskS, dsTray = trayS }

-- One-shot CLI that needs the system bus: connect once, run, disconnect.
withBus :: (DBus.Client -> IO ()) -> IO ()
withBus act = do
  r <- try DBus.connectSystem :: IO (Either SomeException DBus.Client)
  case r of
    Left _  -> return ()
    Right c -> act c >> DBus.disconnect c

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["daemon"]       -> runDaemon
    ["statusd"]      -> loadTheme >>= statusdHealth >>= putStr
    ["web2org"]      -> loadTheme >>= web2orgWidget >>= putStr
    ["displays"]     -> loadTheme >>= displays >>= putStr
    ["battery"]      -> do t <- loadTheme; withBus (\c -> queryUPower c >>= renderBattery t >>= putStr)
    ["power"]        -> do t <- loadTheme; withBus (\c -> queryUPower c >>= renderPower t >>= putStr)
    ["wifi"]         -> do t <- loadTheme; withBus (\c -> queryNMWifi c >>= renderWifi t 5 >>= putStr)
    ["vpn"]          -> do t <- loadTheme; withBus (\c -> queryNMVpn c >>= renderVpn t >>= putStr)
    ["brightness"]   -> loadTheme >>= brightness   >>= putStr
    ["camera"]       -> loadTheme >>= camera       >>= putStr
    ["cputemp"]      -> loadTheme >>= cputemp      >>= putStr
    ["volume"]       -> loadTheme >>= volume       >>= putStr
    ["emacs"]        -> loadTheme >>= emacs        >>= putStr
    ["gpu"]          -> loadTheme >>= gpu          >>= putStr
    ["powerprofile"] -> loadTheme >>= powerprofile >>= putStr
    ["disk"]         -> loadTheme >>= disk         >>= putStr
    ["tray"]         -> loadTheme >>= tray         >>= putStr
    _ -> putStrLn "Usage: xmobar-status {daemon|statusd|web2org|displays|battery|brightness|camera|cputemp|disk|volume|wifi|vpn|emacs|gpu|power|powerprofile}"

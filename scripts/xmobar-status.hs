#!/usr/bin/env cabal
{- cabal:
build-depends: base, directory, filepath, process, bytestring, dbus
-}

module Main where

import Control.Exception (try, SomeException)
import Data.Char (isSpace)
import Data.List (find, intercalate, isPrefixOf, isInfixOf)
import Data.Word (Word8, Word32)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Map.Strict as Map
import System.Directory (listDirectory, doesFileExist, doesDirectoryExist)
import System.Environment (getArgs)
import System.FilePath ((</>))
import System.IO (openFile, IOMode(..), hGetContents', hClose)
import System.Process (readProcess)
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

trim :: String -> String
trim = f . f where f = reverse . dropWhile isSpace

fn1 :: String -> String
fn1 s = "<fn=1>" ++ s ++ "</fn>"

fc :: String -> String -> String
fc color s = "<fc=" ++ color ++ ">" ++ s ++ "</fc>"

icon :: String -> String -> String
icon color glyph = fn1 (fc color glyph)

readInt :: String -> Int
readInt s = case reads (trim s) of
  [(n, _)] -> n
  _        -> 0

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

-- UPower (battery via D-Bus). Avoids vendor-specific sysfs differences
-- (e.g. ThinkPad exposes power_now, Framework exposes current_now).

data UPowerInfo = UPowerInfo
  { upPercent :: Int       -- 0..100
  , upState   :: Word32    -- 0=Unknown 1=Charging 2=Discharging 3=Empty 4=Full ...
  , upWatts   :: Double    -- positive (always magnitude)
  } deriving Show

queryUPower :: IO (Maybe UPowerInfo)
queryUPower = do
  result <- try go :: IO (Either SomeException (Maybe UPowerInfo))
  return $ either (const Nothing) id result
  where
    go = do
      client <- DBus.connectSystem
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
        []      -> DBus.disconnect client >> return Nothing
        (bp:_)  -> do
          info <- readBatteryProps client bp
          DBus.disconnect client
          return (Just info)

    readBatteryProps client objPath = do
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

queryNMWifi :: IO (Maybe NMWifi)
queryNMWifi = do
  result <- try go :: IO (Either SomeException (Maybe NMWifi))
  return $ either (const Nothing) id result
  where
    nmName = DBus.busName_ "org.freedesktop.NetworkManager"
    nmRoot = DBus.objectPath_ "/org/freedesktop/NetworkManager"
    propIf = DBus.interfaceName_ "org.freedesktop.DBus.Properties"

    getProp client objPath iface prop = do
      r <- DBus.call_ client (DBus.methodCall objPath propIf
                              (DBus.memberName_ "Get"))
              { DBus.methodCallDestination = Just nmName
              , DBus.methodCallBody =
                  [ DBus.toVariant (iface :: String)
                  , DBus.toVariant (prop :: String) ] }
      return $ case DBus.methodReturnBody r of
                 [v] -> DBus.fromVariant v :: Maybe DBus.Variant
                 _   -> Nothing

    go = do
      client <- DBus.connectSystem
      reply  <- DBus.call_ client (DBus.methodCall nmRoot
                  (DBus.interfaceName_ "org.freedesktop.NetworkManager")
                  (DBus.memberName_ "GetDevices"))
                  { DBus.methodCallDestination = Just nmName }
      let devs = case DBus.methodReturnBody reply of
                   [v] -> maybe [] id (DBus.fromVariant v :: Maybe [DBus.ObjectPath])
                   _   -> []
      info <- findActiveWifi client devs
      DBus.disconnect client
      return info

    findActiveWifi _ [] = return Nothing
    findActiveWifi client (dp:rest) = do
      mdt <- getProp client dp "org.freedesktop.NetworkManager.Device" "DeviceType"
      let dtype = maybe 0 id (mdt >>= DBus.fromVariant :: Maybe Word32)
      if dtype /= 2     -- 2 = NM_DEVICE_TYPE_WIFI
        then findActiveWifi client rest
        else do
          mIfV <- getProp client dp "org.freedesktop.NetworkManager.Device" "Interface"
          let iface = maybe "" id (mIfV >>= DBus.fromVariant :: Maybe String)
          mApV <- getProp client dp "org.freedesktop.NetworkManager.Device.Wireless" "ActiveAccessPoint"
          case mApV >>= DBus.fromVariant :: Maybe DBus.ObjectPath of
            Nothing                                   -> return Nothing
            Just ap | DBus.formatObjectPath ap == "/" -> return Nothing
            Just ap -> do
              mSsid <- getProp client ap "org.freedesktop.NetworkManager.AccessPoint" "Ssid"
              mStr  <- getProp client ap "org.freedesktop.NetworkManager.AccessPoint" "Strength"
              let ssid = maybe "" BSC.unpack (mSsid >>= DBus.fromVariant :: Maybe BS.ByteString)
                  strg = maybe 0  id          (mStr  >>= DBus.fromVariant :: Maybe Word8)
              return $ Just (NMWifi iface ssid strg)

-- NetworkManager active VPN/WireGuard connection lookup.

queryNMVpn :: IO (Maybe String)
queryNMVpn = do
  result <- try go :: IO (Either SomeException (Maybe String))
  return $ either (const Nothing) id result
  where
    nmName = DBus.busName_ "org.freedesktop.NetworkManager"
    nmRoot = DBus.objectPath_ "/org/freedesktop/NetworkManager"
    propIf = DBus.interfaceName_ "org.freedesktop.DBus.Properties"

    getProp client objPath iface prop = do
      r <- DBus.call_ client (DBus.methodCall objPath propIf
                              (DBus.memberName_ "Get"))
              { DBus.methodCallDestination = Just nmName
              , DBus.methodCallBody =
                  [ DBus.toVariant (iface :: String)
                  , DBus.toVariant (prop :: String) ] }
      return $ case DBus.methodReturnBody r of
                 [v] -> DBus.fromVariant v :: Maybe DBus.Variant
                 _   -> Nothing

    go = do
      client <- DBus.connectSystem
      mActive <- getProp client nmRoot
                   "org.freedesktop.NetworkManager" "ActiveConnections"
      let acs = maybe [] id (mActive >>= DBus.fromVariant :: Maybe [DBus.ObjectPath])
      name <- findVpn client acs
      DBus.disconnect client
      return name

    findVpn _ [] = return Nothing
    findVpn client (ap:rest) = do
      mTy <- getProp client ap "org.freedesktop.NetworkManager.Connection.Active" "Type"
      let ty = maybe "" id (mTy >>= DBus.fromVariant :: Maybe String)
      if ty == "wireguard" || ty == "vpn"
        then do
          mId <- getProp client ap "org.freedesktop.NetworkManager.Connection.Active" "Id"
          let cid = maybe "" id (mId >>= DBus.fromVariant :: Maybe String)
          return (Just cid)
        else findVpn client rest

-- Widgets

battery :: Theme -> IO ()
battery t = do
  mInfo <- queryUPower
  case mInfo of
    Nothing -> return ()
    Just (UPowerInfo cap st _) -> do
      let ico = case st of
                  1 -> "\xF0E7"   -- Charging
                  2 -> "\xF240"   -- Discharging
                  _ -> "\xF1E6"   -- Full / Unknown
          color | cap <= 20 = tErr t
                | cap <= 80 = tWarn t
                | otherwise = tGood t
      putStr $ icon color ico ++ " " ++ show cap ++ "%"

brightness :: Theme -> IO ()
brightness t = do
  mbl <- cachedLookup "/tmp/xmobar-backlight" $
    findFirst "/sys/class/backlight" ""
  case mbl of
    Nothing -> return ()
    Just bl -> do
      cur <- readInt <$> readFileSafe (bl </> "brightness")
      mx  <- readInt <$> readFileSafe (bl </> "max_brightness")
      let pct = if mx > 0 then cur * 100 `div` mx else 0
          color | pct < 25  = tDim t
                | pct < 50  = tMid t
                | pct < 75  = tFrost t
                | otherwise = tWarn t
      putStr $ icon color "\xF0EB" ++ " " ++ show pct ++ "%"

cputemp :: Theme -> IO ()
cputemp t = do
  mhw <- cachedLookup "/tmp/xmobar-cputemp-hwmon" $
    findHwmon ["coretemp", "k10temp"]
  case mhw of
    Nothing -> return ()
    Just hw -> do
      tempS <- readFileSafe (hw </> "temp1_input")
      let temp = readInt tempS `div` 1000
      putStr $ show temp ++ "C"

volume :: Theme -> IO ()
volume t = do
  result <- try (readProcess "wpctl" ["get-volume", "@DEFAULT_AUDIO_SINK@"] "")
            :: IO (Either SomeException String)
  case result of
    Left _    -> putStr "N/A"
    Right out -> do
      let ws = words out
          vol = case drop 1 ws of
                  (v:_) -> show (round (read v * 100 :: Double) :: Int) ++ "%"
                  _     -> "N/A"
          muted = "MUTED" `elem` ws
      if muted
        then putStr $ fc (tErr t) "[M]"
        else putStr vol

wifi :: Theme -> IO ()
wifi t = do
  mw <- queryNMWifi
  case mw of
    Nothing -> putStr $ icon (tDim t) "\xF1EB" ++ " " ++ fc (tDim t) "disconnected"
    Just (NMWifi iface ssid _) -> do
      let stateFile = "/tmp/wifi-status-" ++ iface
      rx <- readInt <$> readFileSafe ("/sys/class/net/" ++ iface ++ "/statistics/rx_bytes")
      tx <- readInt <$> readFileSafe ("/sys/class/net/" ++ iface ++ "/statistics/tx_bytes")
      prev <- readFileSafe stateFile
      let color = case words prev of
            [prS, ptS] ->
              let pr  = readInt prS
                  pt  = readInt ptS
                  dt  = 30  -- xmobar polls wifi every 30s
                  rxR = (rx - pr) `div` dt
                  txR = (tx - pt) `div` dt
              in if rxR > 1000000 || txR > 1000000 then tGood t
                 else if rxR > 100000 || txR > 100000 then tAccent t
                 else if rxR > 1000 || txR > 1000 then tNormal t
                 else tDim t
            _ -> tNormal t
      writeFile stateFile (show rx ++ " " ++ show tx)
      putStr $ icon color "\xF1EB" ++ " " ++ fc color ssid

vpn :: Theme -> IO ()
vpn t = do
  mName <- queryNMVpn
  case mName of
    Nothing   -> putStr $ icon (tDim  t) "\xF0582" ++ " " ++ fc (tDim  t) "off"
    Just name -> putStr $ icon (tGood t) "\xF0582" ++ " " ++ fc (tGood t) name

emacs :: Theme -> IO ()
emacs t = do
  status <- trim <$> readFileSafe "/tmp/emacs-status"
  let color = case status of
        "ready"    -> tGood t
        "starting" -> tWarn t
        "error"    -> tErr t
        _          -> tDim t
  putStr $ icon color "\xE632"

gpu :: Theme -> IO ()
gpu t = do
  let cacheFile = "/tmp/gpu-cards"
  exists <- doesFileExist cacheFile
  if not exists
    then do
      exists' <- doesDirectoryExist "/sys/class/drm"
      if not exists'
        then return ()
        else do
          entries <- listDirectory "/sys/class/drm"
          let cards = filter (\e -> "card" `isPrefixOf` e && all (`elem` "0123456789") (drop 4 e)) entries
          foundAny <- buildGpuCache cacheFile cards
          if not foundAny then return ()
          else gpuOutput t cacheFile
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

gpuOutput :: Theme -> FilePath -> IO ()
gpuOutput t cacheFile = do
  contents <- readFileSafe cacheFile
  parts <- mapM (formatGpuCard t) (filter (not . null) (lines contents))
  let nonEmpty = filter (not . null) parts
  if null nonEmpty then return ()
  else putStr $ icon (tNormal t) "\xF0EA8" ++ " " ++ intercalate "  " nonEmpty ++ " | "

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

power :: Theme -> IO ()
power t = do
  mInfo <- queryUPower
  case mInfo of
    Nothing -> return ()
    Just (UPowerInfo _ st watts) | watts > 0 -> do
      let w10  = round (watts * 10) :: Int
          wInt = w10 `div` 10
          wDec = w10 `mod` 10
          wStr = show wInt ++ "." ++ show wDec ++ "W"
          color | wInt < 15 = tGood t
                | wInt < 25 = tWarn t
                | otherwise = tErr t
      case st of
        2 -> putStr $ icon color    "\xF0E7" ++ " "  ++ wStr  -- Discharging
        1 -> putStr $ icon (tGood t) "\xF0E7" ++ " +" ++ wStr  -- Charging
        _ -> return ()
    _ -> return ()

camera :: Theme -> IO ()
camera t = do
  modules <- readFileSafe "/proc/modules"
  let loaded = any (isPrefixOf "uvcvideo") (lines modules)
      (color, ico) = if loaded
                     then (tGood t, "\xF0208")  -- eye open = camera available
                     else (tErr t, "\xF0209")   -- eye off = camera disabled
  putStr $ icon color ico

main :: IO ()
main = do
  args <- getArgs
  t <- loadTheme
  case args of
    ["battery"]    -> battery t
    ["brightness"] -> brightness t
    ["camera"]     -> camera t
    ["cputemp"]    -> cputemp t
    ["volume"]     -> volume t
    ["wifi"]       -> wifi t
    ["vpn"]        -> vpn t
    ["emacs"]      -> emacs t
    ["gpu"]        -> gpu t
    ["power"]      -> power t
    _              -> putStrLn "Usage: xmobar-status {battery|brightness|camera|cputemp|volume|wifi|vpn|emacs|gpu|power}"

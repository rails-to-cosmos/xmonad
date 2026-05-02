#!/usr/bin/env cabal
{- cabal:
build-depends: base, directory, filepath, process, bytestring
-}

module Main where

import Control.Exception (try, SomeException)
import Data.Char (isSpace)
import Data.List (find, intercalate, isPrefixOf, isInfixOf)
import System.Directory (listDirectory, doesFileExist, doesDirectoryExist)
import System.Environment (getArgs)
import System.FilePath ((</>))
import System.IO (openFile, IOMode(..), hGetContents', hClose)
import System.Process (readProcess)

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

-- Widgets

battery :: Theme -> IO ()
battery t = do
  mbat <- findFirst "/sys/class/power_supply" "BAT"
  case mbat of
    Nothing -> return ()
    Just bat -> do
      capS   <- trim <$> readFileSafe (bat </> "capacity")
      status <- trim <$> readFileSafe (bat </> "status")
      let cap = readInt capS
          ico = case status of
                  "Charging"    -> "\xF0E7"
                  "Discharging" -> "\xF240"
                  _             -> "\xF1E6"
          color | cap <= 20  = tErr t
                | cap <= 80  = tWarn t
                | otherwise  = tGood t
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
  let iface = "wlan0"
      stateFile = "/tmp/wifi-status-" ++ iface
  result <- try (readProcess "iw" ["dev", iface, "link"] "")
            :: IO (Either SomeException String)
  let essid = case result of
        Left _    -> ""
        Right out -> case find ("SSID:" `isPrefixOf`) (map trim (lines out)) of
          Just l  -> trim $ drop 5 l
          Nothing -> ""
  if null essid
    then putStr $ icon (tDim t) "\xF1EB" ++ " " ++ fc (tDim t) "disconnected"
    else do
      rx <- readInt <$> readFileSafe ("/sys/class/net/" ++ iface ++ "/statistics/rx_bytes")
      tx <- readInt <$> readFileSafe ("/sys/class/net/" ++ iface ++ "/statistics/tx_bytes")
      prev <- readFileSafe stateFile
      let color = case words prev of
            [prS, ptS] ->
              let pr = readInt prS
                  pt = readInt ptS
                  dt = 3
                  rxR = (rx - pr) `div` dt
                  txR = (tx - pt) `div` dt
              in if rxR > 1000000 || txR > 1000000 then tGood t
                 else if rxR > 100000 || txR > 100000 then tAccent t
                 else if rxR > 1000 || txR > 1000 then tNormal t
                 else tDim t
            _ -> tNormal t
      writeFile stateFile (show rx ++ " " ++ show tx)
      putStr $ icon color "\xF1EB" ++ " " ++ fc color essid

vpn :: Theme -> IO ()
vpn t = do
  result <- try (readProcess "ip" ["-o", "link", "show", "type", "wireguard"] "")
            :: IO (Either SomeException String)
  let iface = case result of
        Left _    -> ""
        Right out -> case lines out of
          (l:_) -> trim $ takeWhile (\c -> c /= '@' && c /= ':') $ drop 1 $ dropWhile (/= ':') l
          _     -> ""
  if null iface
    then putStr $ icon (tDim t) "\xF0582" ++ " " ++ fc (tDim t) "off"
    else putStr $ icon (tGood t) "\xF0582" ++ " " ++ fc (tGood t) iface

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
        let deviceLink = "/sys/class/drm" </> card </> "device"
        result <- try (readProcess "lspci" ["-s", "00:00.0"] "") :: IO (Either SomeException String)
        -- Get PCI address from symlink
        pciResult <- try (readProcess "readlink" [deviceLink] "") :: IO (Either SomeException String)
        let pci = case pciResult of
              Right p -> let s = trim p in reverse $ takeWhile (/= '/') (reverse s)
              Left _  -> ""
        desc <- if null pci then return ""
                else do
                  r <- try (readProcess "lspci" ["-s", pci] "") :: IO (Either SomeException String)
                  return $ either (const "") trim r
        let label = extractGpuLabel desc card
        appendFile cacheFile (card ++ " " ++ label ++ "\n")
        go rest True

extractGpuLabel :: String -> String -> String
extractGpuLabel desc fallback =
  let afterBracket = drop 1 $ dropWhile (/= ']') desc
      trimmed = dropWhile (== ' ') afterBracket
      beforeBracket = takeWhile (/= '[') trimmed
      cleaned = reverse $ dropWhile isSpace $ reverse beforeBracket
  in if null cleaned then fallback else cleaned

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
  mbat <- findFirst "/sys/class/power_supply" "BAT"
  case mbat of
    Nothing -> return ()
    Just bat -> do
      vS <- trim <$> readFileSafe (bat </> "voltage_now")
      cS <- trim <$> readFileSafe (bat </> "current_now")
      status <- trim <$> readFileSafe (bat </> "status")
      let v = readInt vS                    -- uV
          c = abs (readInt cS)              -- uA (abs in case kernel reports signed)
          w10 = if v > 0 && c > 0           -- 0.1W units
                  then (v `div` 1000) * (c `div` 1000) `div` 100000
                  else 0
          wInt = w10 `div` 10
          wDec = w10 `mod` 10
          wStr = show wInt ++ "." ++ show wDec ++ "W"
          color | wInt < 15  = tGood t
                | wInt < 25  = tWarn t
                | wInt < 40  = tErr t
                | otherwise  = tErr t
      case status of
        "Discharging" -> putStr $ icon color "\xF0E7" ++ " " ++ wStr
        "Charging"    -> putStr $ icon (tGood t) "\xF0E7" ++ " +" ++ wStr
        _             -> return ()

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

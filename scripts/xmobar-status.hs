#!/usr/bin/env cabal
{- cabal:
build-depends: base, directory, filepath, process, bytestring
-}

module Main where

import Control.Exception (try, SomeException)
import Data.Char (isSpace)
import Data.List (find, isPrefixOf)
import System.Directory (listDirectory, doesFileExist, doesDirectoryExist)
import System.Environment (getArgs)
import System.FilePath ((</>))
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
  result <- try (readFile path) :: IO (Either SomeException String)
  return $ either (const "") id result

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
      putStr $ icon color "\xF0EB"

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

main :: IO ()
main = do
  args <- getArgs
  t <- loadTheme
  case args of
    ["battery"]    -> battery t
    ["brightness"] -> brightness t
    ["cputemp"]    -> cputemp t
    ["volume"]     -> volume t
    _              -> putStrLn "Usage: xmobar-status {battery|brightness|cputemp|volume}"

import Data.Bits ((.&.), (.|.))
import XMonad
import XMonad.Hooks.DynamicLog
import XMonad.Hooks.EwmhDesktops
import XMonad.Hooks.ManageDocks
import XMonad.Layout.NoBorders (noBorders, smartBorders)
import XMonad.Layout.Spacing
import XMonad.Layout.ToggleLayouts (ToggleLayout (..), toggleLayouts)
import XMonad.Util.EZConfig (additionalKeysP)
import XMonad.Util.Run (spawnPipe)
import XMonad.Util.SpawnOnce

import System.IO (hPutStrLn)

myTerminal :: String
myTerminal = "alacritty"

myModMask :: KeyMask
myModMask = controlMask .|. mod1Mask

myBorderWidth :: Dimension
myBorderWidth = 2

myNormalBorderColor :: String
myNormalBorderColor = "#444444"

myFocusedBorderColor :: String
myFocusedBorderColor = "#6790eb"

myWorkspaces :: [String]
myWorkspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

mySpacing = spacingRaw False (Border 4 4 4 4) True (Border 4 4 4 4) True

myLayout = toggleLayouts (noBorders Full) $ avoidStruts $ smartBorders $ mySpacing $ tiled ||| Mirror tiled ||| Full
  where
    tiled = Tall 1 (3 / 100) (1 / 2)

myStartupHook :: X ()
myStartupHook = do
    spawnOnce "setxkbmap -layout us,ru -option ''"
    spawnOnce "~/.config/xmonad/setup-inputs.sh"
    spawnOnce "stalonetray --geometry 5x1+0+0 --icon-size 20 --slot-size 24 --bg '#1a1b26' --icon-gravity NE --kludges force_icons_size -d none --window-strut top"

myManageHook =
    composeAll
        [ className =? "Gimp" --> doFloat
        , className =? "MPlayer" --> doFloat
        ]

myKeys :: [(String, X ())]
myKeys =
    [ ("M-<Space>", spawn "dmenu_run")
    , ("M-<Return>", spawn myTerminal)
    , ("M-b", sendMessage ToggleStruts)
    , ("M-f", sendMessage (Toggle "Full"))
    , ("M-t", sendMessage NextLayout)
    , ("M-S-<Space>", spawn "setxkbmap -query | grep -q 'layout:.*us,' && setxkbmap ru || setxkbmap us")
    ]

main :: IO ()
main = do
    xmproc <- spawnPipe "xmobar ~/.config/xmobar/xmobarrc"
    xmonad $
        ewmhFullscreen $
            ewmh $
                docks
                    def
                        { terminal = myTerminal
                        , modMask = myModMask
                        , borderWidth = myBorderWidth
                        , normalBorderColor = myNormalBorderColor
                        , focusedBorderColor = myFocusedBorderColor
                        , workspaces = myWorkspaces
                        , layoutHook = myLayout
                        , manageHook = myManageHook <+> manageHook def
                        , startupHook = myStartupHook
                        , logHook =
                            dynamicLogWithPP
                                xmobarPP
                                    { ppOutput = hPutStrLn xmproc
                                    , ppTitle = xmobarColor "#6790eb" "" . shorten 50
                                    , ppCurrent = xmobarColor "#6790eb" "" . wrap "[" "]"
                                    , ppHidden = xmobarColor "#888888" ""
                                    , ppHiddenNoWindows = xmobarColor "#555555" ""
                                    , ppSep = "  |  "
                                    }
                        }
                    `additionalKeysP` myKeys

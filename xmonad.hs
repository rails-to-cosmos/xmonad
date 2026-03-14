import Data.Bits ((.|.))
import XMonad
import XMonad.Hooks.DynamicLog
import XMonad.Hooks.EwmhDesktops
import XMonad.Hooks.ManageDocks
import XMonad.Layout.NoBorders (noBorders, smartBorders)
import XMonad.Layout.Spacing
import XMonad.Layout.ToggleLayouts (ToggleLayout (..), toggleLayouts)
import XMonad.Util.EZConfig (additionalKeysP, additionalKeys)
import qualified XMonad.StackSet as W
import XMonad.Util.NamedScratchpad
import Graphics.X11.Types (xK_Tab)
import XMonad.Util.Run (spawnPipe)
import XMonad.Util.SpawnOnce

import System.IO (hPutStrLn)

myTerminal :: String
myTerminal = "alacritty"

myModMask :: KeyMask
myModMask = controlMask .|. mod1Mask

rofiFlags :: String
rofiFlags = "-kb-row-down 'Control+n' -kb-row-up 'Control+p'"

myBorderWidth :: Dimension
myBorderWidth = 2

myNormalBorderColor :: String
myNormalBorderColor = "#444444"

myAccentColor :: String
myAccentColor = "#6790eb"

myFocusedBorderColor :: String
myFocusedBorderColor = myAccentColor

myWorkspaces :: [String]
myWorkspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

mySpacing = spacingRaw False (Border 4 4 4 4) True (Border 4 4 4 4) True

myLayout = toggleLayouts (noBorders Full) $ avoidStruts $ smartBorders $ mySpacing $ tiled ||| Mirror tiled ||| Full
  where
    tiled = Tall 1 (3 / 100) (1 / 2)

myStartupHook :: X ()
myStartupHook = do
    spawn "setxkbmap -layout us,ru -option '' -option ctrl:nocaps -option grp:shifts_toggle"
    spawn "~/.config/xmonad/setup-inputs.sh"
    spawnOnce "dunst"
    spawnOnce "stalonetray --geometry 5x1+0+0 --icon-size 20 --slot-size 24 --bg '#1a1b26' --icon-gravity NE --kludges force_icons_size -d none --window-strut top"
    spawnOnce "redshift -l 52.37:4.90"
    spawn "emacsclient -e '(kill-emacs)' 2>/dev/null; echo 'starting' > /tmp/emacs-status; emacs --daemon && echo 'ready' > /tmp/emacs-status || echo 'error' > /tmp/emacs-status"

myScratchpads :: [NamedScratchpad]
myScratchpads =
    [ NS "terminal" (myTerminal ++ " --class scratchterm") (className =? "scratchterm")
        (customFloating $ W.RationalRect 0.1 0.05 0.8 0.4)
    , NS "btop" (myTerminal ++ " --class scratchbtop -e btop") (className =? "scratchbtop")
        (customFloating $ W.RationalRect 0.1 0.1 0.8 0.8)
    , NS "pavucontrol" "pavucontrol" (className =? "pavucontrol")
        (customFloating $ W.RationalRect 0.2 0.2 0.6 0.6)
    , NS "emacs-scratch" "emacsclient -c -F '((name . \"emacs-scratch\"))'" (title =? "emacs-scratch")
        (customFloating $ W.RationalRect 0.15 0.1 0.7 0.8)
    ]

myManageHook =
    composeAll
        [ className =? "Gimp" --> doFloat
        , className =? "MPlayer" --> doFloat
        ]
        <+> namedScratchpadManageHook myScratchpads

myKeys :: [(String, X ())]
myKeys =
    [ ("M1-q", kill)
    , ("M-<Return>", spawn "emacsclient -c")
    , ("M-b", sendMessage ToggleStruts)
    , ("M-f", sendMessage (Toggle "Full"))
    , ("M-t", sendMessage NextLayout)
    , ("M-<Space>", spawn $ "rofi -show combi -combi-modes 'window,drun,run' " ++ rofiFlags)
    , ("M-S-<Space>", spawn $ "rofi -show combi -combi-modes 'drun,run' -run-command 'env DRI_PRIME=1 {cmd}' -drun-command 'env DRI_PRIME=1 {exec}' " ++ rofiFlags)
    , ("M-S-t", namedScratchpadAction myScratchpads "terminal")
    , ("M-s", namedScratchpadAction myScratchpads "btop")
    , ("M-v", namedScratchpadAction myScratchpads "pavucontrol")
    , ("M-c", spawn "telegram")
    , ("M-S-c", spawn "slack")
    , ("M-e", namedScratchpadAction myScratchpads "emacs-scratch")
    , ("M-<Escape>", spawn $ "echo -e 'Lock\nLogout\nSuspend\nReboot\nShutdown' | rofi -dmenu -p 'Power' " ++ rofiFlags ++ " | xargs -I{} sh -c 'case {} in Lock) loginctl lock-session;; Logout) xmonad --restart && killall xmonad;; Suspend) systemctl suspend;; Reboot) systemctl reboot;; Shutdown) systemctl poweroff;; esac'")
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
                                    , ppTitle = xmobarColor myAccentColor "" . shorten 50
                                    , ppCurrent = xmobarColor myAccentColor "" . wrap "[" "]"
                                    , ppHidden = xmobarColor "#888888" ""
                                    , ppHiddenNoWindows = xmobarColor "#555555" ""
                                    , ppSep = "  |  "
                                    }
                        }
                    `additionalKeysP` myKeys
                    `additionalKeys` [ ((mod1Mask, xK_Tab), windows W.focusDown)
                                      , ((mod1Mask .|. shiftMask, xK_Tab), windows W.focusUp)
                                      ]

import Data.Bits ((.|.))
import XMonad
import XMonad.Hooks.DynamicLog
import XMonad.Hooks.EwmhDesktops
import XMonad.Hooks.ManageDocks
import XMonad.Actions.CycleWS (prevWS, nextWS, shiftToPrev, shiftToNext)
import XMonad.Layout.NoBorders (noBorders, smartBorders)
import XMonad.Layout.Spacing
import XMonad.Layout.ToggleLayouts (ToggleLayout (..), toggleLayouts)
import XMonad.Util.EZConfig (additionalKeysP)
import qualified XMonad.StackSet as W
import XMonad.Util.NamedScratchpad
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
myNormalBorderColor = "#223959"

myAccentColor :: String
myAccentColor = "#4CB5F5"

myFocusedBorderColor :: String
myFocusedBorderColor = myAccentColor

myWorkspaces :: [String]
myWorkspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

mySpacing = spacingRaw False (Border 4 4 4 4) True (Border 4 4 4 4) True

-- avoidStruts tells layouts to reserve screen space for dock windows (like xmobar)
-- so they don't get overlapped by tiled windows
myLayout = avoidStruts $ toggleLayouts (noBorders Full) $ smartBorders $ mySpacing $ tiled ||| Mirror tiled ||| Full
  where
    tiled = Tall 1 (3 / 100) (1 / 2)

myStartupHook :: X ()
myStartupHook = do
    spawn "setxkbmap -layout us,ru -option '' -option grp:shifts_toggle"
    spawn "~/.config/xmonad/scripts/setup-inputs.sh"
    spawn "~/.config/xmonad/scripts/audio-fix.sh"
    spawnOnce "dunst"
    spawnOnce "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
    spawnOnce "stalonetray --geometry 5x1+0+0 --icon-size 20 --slot-size 24 --bg '#000000' --icon-gravity NE --kludges force_icons_size -d none --window-strut top"
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
    [ ("C-q", kill)
    , ("M-<Return>", spawn "emacsclient -c")
    , ("M-b", sendMessage ToggleStruts)
    , ("M-f", sendMessage (Toggle "Full"))
    , ("M-t", sendMessage NextLayout)
    , ("M-<Space>", spawn $ "rofi -show combi -combi-modes 'window,drun,run' " ++ rofiFlags)
    , ("M-S-<Space>", spawn $ "rofi -show combi -combi-modes 'drun,run' -run-command 'env DRI_PRIME=1 {cmd}' -drun-command 'env DRI_PRIME=1 {exec}' " ++ rofiFlags)
    , ("M-S-t", namedScratchpadAction myScratchpads "terminal")
    , ("M-s", namedScratchpadAction myScratchpads "btop")
    , ("M-v", namedScratchpadAction myScratchpads "pavucontrol")
    , ("M-e", namedScratchpadAction myScratchpads "emacs-scratch")
    , ("M-S-v", spawn "sh -c 'if lsmod | grep -q uvcvideo; then sudo modprobe -r uvcvideo; else sudo modprobe uvcvideo; fi'")
    , ("M-S-k", prevWS)
    , ("M-S-j", nextWS)
    , ("C-M-<Left>", prevWS)
    , ("C-M-<Right>", nextWS)
    , ("C-M-S-<Left>", shiftToPrev >> prevWS)
    , ("C-M-S-<Right>", shiftToNext >> nextWS)
    , ("C-M-q", spawn "xmonad --recompile && xmonad --restart")
    , ("<XF86MonBrightnessDown>", spawn "brightnessctl --class=backlight set 5%-")
    , ("<XF86MonBrightnessUp>", spawn "brightnessctl --class=backlight set +5%")
    , ("M-S-g", spawn "~/.config/xmonad/scripts/dgpu-control.sh")
    , ("M-S-r", spawn "~/.config/xmonad/scripts/refresh-rate.sh")
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
                                    , ppLayout = const ""
                                    , ppTitle = xmobarColor myAccentColor "" . shorten 50
                                    , ppCurrent = xmobarColor myAccentColor "" . wrap "[" "]"
                                    , ppHidden = xmobarColor "#C0C5CF" ""
                                    , ppHiddenNoWindows = xmobarColor "#39393D" ""
                                    , ppSep = "  |  "
                                    }
                        }
                    `additionalKeysP` myKeys

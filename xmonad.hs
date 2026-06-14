import Data.Bits ((.|.))
import XMonad
import XMonad.Hooks.EwmhDesktops
import XMonad.Hooks.ManageDocks
import XMonad.Hooks.StatusBar
import XMonad.Hooks.StatusBar.PP
import XMonad.Hooks.Rescreen (addRandrChangeHook)
import XMonad.Actions.CycleWS (prevWS, nextWS, shiftToPrev, shiftToNext)
import XMonad.Layout.NoBorders (noBorders, smartBorders)
import XMonad.Layout.Spacing
import XMonad.Layout.ToggleLayouts (ToggleLayout (..), toggleLayouts)
import XMonad.Util.EZConfig (additionalKeysP)
import qualified XMonad.StackSet as W
import XMonad.Util.NamedScratchpad
import XMonad.Util.SpawnOnce

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
    -- spawn "setxkbmap -layout us,ru -option '' -option grp:shifts_toggle"
    spawn "setxkbmap -layout us,ru -option '' -option ctrl:nocaps -option grp:shifts_toggle"
    spawn "~/.config/xmonad/scripts/setup-inputs.sh"
    spawn "~/.config/xmonad/scripts/caps-off.sh"
    -- spawn "~/.config/xmonad/scripts/kmonad-start.sh"
    spawn "~/.config/xmonad/scripts/audio-fix.sh"
    -- Rebuild the status binary, then bounce the daemon child so the supervisor
    -- respawns it with the fresh binary (the supervisor itself holds the FIFO
    -- open, so this bounce doesn't blank the bar), then ensure the supervisor
    -- is running. Sequenced in one spawn so order is deterministic.
    spawn "FORCE_REBUILD=1 ~/.config/xmonad/scripts/build-xmobar-status.sh && notify-send -i dialog-information 'xmobar-status' 'Rebuilt successfully' || notify-send -u critical -i dialog-error 'xmobar-status' 'Build failed'; pkill -f '[x]mobar-status daemon' 2>/dev/null; ~/.config/xmonad/scripts/xmobar-statusd-run.sh &"
    -- spawn "sudo -n ~/.config/xmonad/scripts/power-tweaks.sh"
    spawnOnce "dunst"
    spawnOnce "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
    -- spawnOnce "stalonetray --geometry 5x1+0+0 --icon-size 20 --slot-size 24 --bg '#000000' --icon-gravity NE --kludges force_icons_size -d none --window-strut top"
    spawnOnce "redshift -l 52.37:4.90"
    spawnOnce "emacsclient -e '(kill-emacs)' 2>/dev/null; echo 'starting' > /tmp/emacs-status; emacs --daemon && echo 'ready' > /tmp/emacs-status || echo 'error' > /tmp/emacs-status"

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
        , className =? "web2org-term" --> customFloating (W.RationalRect 0.15 0.15 0.7 0.7)
        , className =? "power-dash" --> customFloating (W.RationalRect 0.12 0.1 0.62 0.8)
        ]
        <+> namedScratchpadManageHook myScratchpads

myKeys :: [(String, X ())]
myKeys =
    [ ("C-q", kill)
    , ("M-<Return>", spawn "emacsclient -c")
    , ("M-f", sendMessage ToggleStruts)
    , ("M-t", sendMessage NextLayout)
    , ("M-<Space>", spawn $ "rofi -show combi -combi-modes 'window,drun,run' " ++ rofiFlags)
    -- Moonlander: tap of the Ctrl+Alt thumb key sends F13 -> launcher
    , ("<F13>", spawn $ "rofi -show combi -combi-modes 'window,drun,run' " ++ rofiFlags)
    , ("M-S-<Space>", spawn $ "rofi -show combi -combi-modes 'drun,run' -run-command 'env DRI_PRIME=1 {cmd}' -drun-command 'env DRI_PRIME=1 {exec}' " ++ rofiFlags)
    , ("M-S-t", namedScratchpadAction myScratchpads "terminal")
    , ("M-s", namedScratchpadAction myScratchpads "btop")
    , ("M-v", namedScratchpadAction myScratchpads "pavucontrol")
    , ("M-e", namedScratchpadAction myScratchpads "emacs-scratch")
    , ("M-S-v", spawn "sh -c 'if lsmod | grep -q uvcvideo; then sudo modprobe -r uvcvideo; else sudo modprobe uvcvideo; fi'")
    , ("M-S-k", prevWS)
    , ("M-S-j", nextWS)
    , ("M-h", prevWS)
    , ("M-l", nextWS)
    , ("C-M-<Left>", prevWS)
    , ("C-M-<Right>", nextWS)
    , ("C-M-S-<Left>", shiftToPrev >> prevWS)
    , ("C-M-S-<Right>", shiftToNext >> nextWS)
    , ("C-M-q", spawn "xmonad --recompile && xmonad --restart")
    , ("<XF86MonBrightnessDown>", spawn "brightnessctl --class=backlight set 5%-")
    , ("<XF86MonBrightnessUp>", spawn "brightnessctl --class=backlight set +5%")
    , ("M-S-<Return>", withFocused $ windows . W.sink)
    , ("M-S-g", spawn "~/.config/xmonad/scripts/dgpu-control.sh")
    , ("M-S-r", spawn "~/.config/xmonad/scripts/refresh-rate.sh")
    , ("M-S-p", spawn "~/.config/xmonad/scripts/power-profile.sh")
    , ("M-S-w", spawn "alacritty --class power-dash -e ~/.config/xmonad/scripts/power-dashboard --watch 2")
    , ("M-o", spawn "~/.config/xmonad/scripts/web2org.sh")
    , ("M-S-o", spawn "WEB_CAPTURE_TERM=1 ~/.config/xmonad/scripts/web2org.sh")
    , ("M-<Escape>", spawn $ "echo -e 'Lock\nLogout\nSuspend\nReboot\nShutdown' | rofi -dmenu -p 'Power' " ++ rofiFlags ++ " | xargs -I{} sh -c 'case {} in Lock) loginctl lock-session;; Logout) xmonad --restart && killall xmonad;; Suspend) systemctl suspend;; Reboot) systemctl reboot;; Shutdown) systemctl poweroff;; esac'")
    ]

-- Workspace/title pretty-printer piped to each bar's StdinReader.
myPP :: PP
myPP = xmobarPP
    { ppLayout = const ""
    , ppTitle = xmobarColor myAccentColor "" . shorten 50
    , ppCurrent = xmobarColor myAccentColor "" . wrap "[" "]"
    , ppHidden = xmobarColor "#C0C5CF" ""
    , ppHiddenNoWindows = xmobarColor "#39393D" ""
    , ppSep = "  |  "
    }

-- One xmobar per screen, spawned/killed automatically by dynamicSBs as screens
-- come and go (e.g. plugging/unplugging a monitor). ScreenId is Integral, so
-- fromIntegral gives the -x index.
mkBar :: ScreenId -> X StatusBarConfig
mkBar sid = io $ statusBarPipe
    ("xmobar -x " ++ show (fromIntegral sid :: Int) ++ " ~/.config/xmobar/xmobarrc")
    (pure myPP)

main :: IO ()
main = xmonad
     $ ewmhFullscreen
     $ ewmh
     $ docks
     -- dynamicSBs manages per-screen bars across screen changes; addRandrChangeHook
     -- runs `xrandr --auto` on monitor hotplug so a disconnected output's CRTC is
     -- dropped (otherwise Xinerama/countScreens stay stale and a phantom bar lingers).
     $ dynamicSBs mkBar
     $ addRandrChangeHook (spawn "xrandr --auto")
     $ def
         { terminal = myTerminal
         , modMask = myModMask
         , borderWidth = myBorderWidth
         , normalBorderColor = myNormalBorderColor
         , focusedBorderColor = myFocusedBorderColor
         , workspaces = myWorkspaces
         , layoutHook = myLayout
         , manageHook = myManageHook <+> manageHook def
         , startupHook = myStartupHook
         }
     `additionalKeysP` myKeys

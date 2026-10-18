using MudRunner.Vehicles;
using UnityEngine;
using UnityEngine.InputSystem;

namespace MudRunner.Game
{
    /// <summary>
    /// Keyboard + mouse (and basic gamepad) driver input for the player-controlled <see cref="Vehicle"/>.
    /// Reads devices directly (no input-action asset) so it works the same in editor, tests and builds.
    ///
    /// W/S or Up/Down  throttle / brake (reverse pedal when stopped, automatic gearbox)
    /// A/D or Left/Right steer          Space handbrake
    /// Left Shift / Left Ctrl  shift up / down (manual gearbox)     M  toggle automatic / manual
    /// R  low / high range    T  all-wheel drive    F  front diff lock    G  rear diff lock(s)    V  centre diff lock
    /// I  engine on/off       Backspace  recover (flip-reset, costs fuel/time)
    /// </summary>
    [DefaultExecutionOrder(-30)]
    public sealed class PlayerVehicleInput : MonoBehaviour
    {
        public Vehicle vehicle;
        public bool inputEnabled = true;
        [Tooltip("Keyboard steering smoothing (units/s); keeps keyboard from slamming lock-to-lock.")]
        public float keyboardSteerRate = 3.2f;
        public float keyboardReturnRate = 4.5f;

        float steerKey;
        public bool wantsRecover { get; private set; }

        // edge events other systems can poll (cleared each Update)
        public bool pressedHeadlights, pressedCamera, pressedMap, pressedWinchAttach, pressedHelp;
        public float winchAxis;     // +1 reel in, -1 reel out

        void Update()
        {
            pressedHeadlights = pressedCamera = pressedMap = pressedWinchAttach = pressedHelp = false;
            wantsRecover = false;
            if (vehicle == null || !inputEnabled) { winchAxis = 0f; return; }
            var kb = Keyboard.current;
            var pad = Gamepad.current;
            if (kb == null && pad == null) return;

            float thr = 0f, brk = 0f, steerTarget = 0f; bool hand = false;
            if (kb != null)
            {
                if (kb.wKey.isPressed || kb.upArrowKey.isPressed) thr = 1f;
                if (kb.sKey.isPressed || kb.downArrowKey.isPressed) brk = 1f;
                if (kb.aKey.isPressed || kb.leftArrowKey.isPressed) steerTarget -= 1f;
                if (kb.dKey.isPressed || kb.rightArrowKey.isPressed) steerTarget += 1f;
                hand = kb.spaceKey.isPressed;
                if (kb.leftShiftKey.wasPressedThisFrame) vehicle.input.shiftUp = true;
                if (kb.leftCtrlKey.wasPressedThisFrame) vehicle.input.shiftDown = true;
                if (kb.mKey.wasPressedThisFrame) vehicle.ToggleGearMode();
                if (kb.rKey.wasPressedThisFrame) vehicle.ToggleLowRange();
                if (kb.tKey.wasPressedThisFrame) vehicle.ToggleAwd();
                if (kb.fKey.wasPressedThisFrame) vehicle.ToggleAxleLock(0);
                if (kb.gKey.wasPressedThisFrame) { for (int a = 1; a < vehicle.def.axles.Length; a++) vehicle.ToggleAxleLock(a); }
                if (kb.vKey.wasPressedThisFrame) vehicle.ToggleCentreLock();
                if (kb.iKey.wasPressedThisFrame) vehicle.ToggleEngine();
                if (kb.backspaceKey.wasPressedThisFrame) wantsRecover = true;
                pressedHeadlights = kb.lKey.wasPressedThisFrame;
                pressedCamera = kb.cKey.wasPressedThisFrame;
                pressedMap = kb.tabKey.wasPressedThisFrame;
                pressedWinchAttach = kb.zKey.wasPressedThisFrame;
                pressedHelp = kb.hKey.wasPressedThisFrame;
                winchAxis = (kb.eKey.isPressed ? 1f : 0f) - (kb.qKey.isPressed ? 1f : 0f);
            }
            float steerNow = steerKey;
            if (Mathf.Abs(steerTarget) > 0.01f)
                steerNow = Mathf.MoveTowards(steerNow, steerTarget, keyboardSteerRate * Time.unscaledDeltaTime);
            else steerNow = Mathf.MoveTowards(steerNow, 0f, keyboardReturnRate * Time.unscaledDeltaTime);
            steerKey = steerNow;
            float steer = steerKey;

            if (pad != null)
            {
                float rt = pad.rightTrigger.ReadValue(), lt = pad.leftTrigger.ReadValue();
                if (rt > thr) thr = rt; if (lt > brk) brk = lt;
                float sx = pad.leftStick.x.ReadValue();
                if (Mathf.Abs(sx) > 0.1f) steer = sx;
                hand |= pad.buttonSouth.isPressed;
                if (pad.rightShoulder.wasPressedThisFrame) vehicle.input.shiftUp = true;
                if (pad.leftShoulder.wasPressedThisFrame) vehicle.input.shiftDown = true;
                if (pad.buttonWest.wasPressedThisFrame) vehicle.ToggleLowRange();
                if (pad.buttonNorth.wasPressedThisFrame) vehicle.ToggleAwd();
                if (pad.dpad.left.wasPressedThisFrame) vehicle.ToggleAxleLock(0);
                if (pad.dpad.right.wasPressedThisFrame) { for (int a = 1; a < vehicle.def.axles.Length; a++) vehicle.ToggleAxleLock(a); }
                if (pad.dpad.up.wasPressedThisFrame) pressedCamera = true;
            }

            var inp = vehicle.input;
            inp.throttle = thr; inp.brake = brk; inp.steer = steer; inp.handbrake = hand;
            vehicle.input = inp;
        }
    }
}

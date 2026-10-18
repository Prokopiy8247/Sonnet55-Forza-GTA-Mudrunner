using UnityEngine;

namespace MudRunner.Game
{
    /// <summary>Minimal chase camera (placeholder until the full CameraRig replaces it).</summary>
    public sealed class SimpleChaseCamera : MonoBehaviour
    {
        public Transform target;
        public float distance = 9f, height = 3.2f, lookHeight = 1.2f, followSpeed = 4f;
        Vector3 smoothPos; float yaw;

        void LateUpdate()
        {
            if (target == null && GameManager.Instance != null && GameManager.Instance.Player != null) target = GameManager.Instance.Player.transform;
            if (target == null) return;
            float targetYaw = target.eulerAngles.y;
            yaw = Mathf.LerpAngle(yaw, targetYaw, 1f - Mathf.Exp(-followSpeed * Time.deltaTime));
            Vector3 back = Quaternion.Euler(0, yaw, 0) * Vector3.back;
            Vector3 want = target.position + back * distance + Vector3.up * height;
            smoothPos = Vector3.Lerp(smoothPos == Vector3.zero ? want : smoothPos, want, 1f - Mathf.Exp(-8f * Time.deltaTime));
            transform.position = smoothPos;
            transform.rotation = Quaternion.LookRotation(target.position + Vector3.up * lookHeight - smoothPos);
        }
    }
}

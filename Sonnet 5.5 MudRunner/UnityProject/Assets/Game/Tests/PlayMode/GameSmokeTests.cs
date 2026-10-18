using System.Collections;
using MudRunner.Game;
using MudRunner.Ground;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace MudRunner.Tests
{
    /// <summary>Loads the real Game scene and checks that the game starts in a vehicle and is drivable.</summary>
    public class GameSmokeTests
    {
        [SetUp] public void SetUp() { Time.captureFramerate = 60; }
        [TearDown] public void TearDown() { Time.captureFramerate = 0; }

        [UnityTest]
        public IEnumerator GameScene_StartsInVehicle_AndDrives([ValueSource(typeof(GameManager), nameof(GameManager.VehicleKeys))] string key)
        {
            var op = SceneManager.LoadSceneAsync("Game");
            while (!op.isDone) yield return null;
            yield return null; yield return null;
            var gm = GameManager.Instance;
            Assert.IsNotNull(gm, "GameManager exists");
            gm.SwitchPlayerVehicle(key);
            yield return new WaitForSeconds(0.5f);
            Assert.IsNotNull(gm.Player, "player vehicle spawned");
            var v = gm.Player;
            Vector3 p0 = v.transform.position;
            var inp = v.input; inp.throttle = 1f; inp.handbrake = false; v.input = inp;
            float t0 = Time.time;
            while (Time.time - t0 < 10f) yield return null;
            float dist = (v.transform.position - p0).magnitude;
            Debug.Log("[MudRunner] SMOKE " + key + ": drove " + dist.ToString("F1") + " m in 10 s, speed=" + v.speedKmh.ToString("F1") + " km/h gear=" + v.drivetrain.GearLabel + " fuel=" + v.fuel.ToString("F1") + "L");
            Assert.Greater(dist, 8f, "vehicle moves under throttle");
            Assert.IsFalse(float.IsNaN(v.transform.position.x));
            Assert.IsNotNull(GroundService.Instance);
        }

        /// <summary>Regression: the menu's Free Drive / scenarios call StartWorld again; the old GroundService is destroyed at end of frame and used to take the new one with it (no ground, vehicle fell forever).</summary>
        [UnityTest]
        public IEnumerator StartWorld_Twice_KeepsGroundAndVehicleStaysOnIt()
        {
            var op = SceneManager.LoadSceneAsync("Game");
            while (!op.isDone) yield return null;
            yield return null; yield return null;
            var gm = GameManager.Instance;
            Assert.IsNotNull(gm);
            foreach (var kind in new[] { WorldKind.Wilderness, WorldKind.ProvingGround })
            {
                gm.StartWorld(kind, "scout");
                yield return new WaitForSeconds(2.0f);
                Assert.IsNotNull(GroundService.Instance, kind + ": GroundService singleton survives the world switch");
                Assert.AreSame(gm.Ground, GroundService.Instance);
                var p = gm.Player.transform.position;
                float gh = GroundService.Instance.GroundHeight(p.x, p.z);
                Assert.Less(Mathf.Abs(p.y - gh), 1.5f, kind + ": vehicle rests on the ground (y=" + p.y.ToString("F2") + ", ground=" + gh.ToString("F2") + ")");
                Assert.Greater(gm.Player.groundedWheels, 2);
            }
        }
    }
}

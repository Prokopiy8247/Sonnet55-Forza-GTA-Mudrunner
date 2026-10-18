using System.Collections;
using MudRunner.Testing;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace MudRunner.Tests
{
    /// <summary>Runs the in-game automated physics suite (the same code behind the debug-menu button) in batch mode.</summary>
    public class SuiteTests
    {
        [UnityTest, Timeout(1800000)]
        public IEnumerator RuntimeSuite_AllChecksMeetExpectations()
        {
            Time.captureFramerate = 60;
            var s = RuntimePhysicsSuite.Run(false);
            while (s.Running) yield return null;
            Time.captureFramerate = 0;
            Debug.Log("[MudRunner] SUITE_SUMMARY passed=" + s.Passed + " failed=" + s.Failed);
            Assert.AreEqual(0, s.Failed, "unexpected physics results:\n" + s.Report);
        }
    }
}

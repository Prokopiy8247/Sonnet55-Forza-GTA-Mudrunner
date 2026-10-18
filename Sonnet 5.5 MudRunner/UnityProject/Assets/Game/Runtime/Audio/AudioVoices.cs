using MudRunner.Audio.Dsp;
using UnityEngine;

namespace MudRunner.Audio
{
    /// <summary>
    /// Shared helpers for the procedural voices. Every voice is an AudioSource that loops a one-sample-long silent clip; the
    /// real signal is written into the buffer by OnAudioFilterRead (audio thread). That keeps Unity's 3D panning, distance
    /// attenuation, mixer routing and pause handling, while the sound itself is pure code.
    /// </summary>
    public static class AudioVoiceUtil
    {
        static AudioClip silent;

        public static AudioClip SilentClip
        {
            get
            {
                if (silent == null)
                {
                    silent = AudioClip.Create("MR_Silence", 1024, 1, 44100, false);
                    silent.SetData(new float[1024], 0);
                }
                return silent;
            }
        }

        /// <summary>Custom rolloff curve (x = distance / maxDistance): full volume to ~8 m, -6 dB at ~20 m, -18 dB at ~65 m, silent at max.</summary>
        public static AnimationCurve RolloffCurve(float maxDistance)
        {
            float d(float meters) { return Mathf.Clamp01(meters / maxDistance); }
            return new AnimationCurve(
                new Keyframe(0f, 1f), new Keyframe(d(8f), 0.9f), new Keyframe(d(20f), 0.5f), new Keyframe(d(45f), 0.22f),
                new Keyframe(d(90f), 0.08f), new Keyframe(d(maxDistance * 0.7f), 0.025f), new Keyframe(1f, 0f));
        }

        public static AudioSource AddSource(GameObject go, bool spatial, float maxDistance = 220f)
        {
            var src = go.AddComponent<AudioSource>();
            src.clip = SilentClip;
            src.loop = true;
            src.playOnAwake = false;
            src.dopplerLevel = 0f;               // Doppler is applied inside the synth (the synthesized signal is not resampled by Unity)
            src.volume = 1f;
            src.priority = 64;
            src.spatialBlend = spatial ? 1f : 0f;
            if (spatial)
            {
                src.minDistance = 5f; src.maxDistance = maxDistance;
                src.rolloffMode = AudioRolloffMode.Custom;
                src.SetCustomCurve(AudioSourceCurveType.CustomRolloff, RolloffCurve(maxDistance));
                src.spread = 50f;
            }
            return src;
        }
    }

    /// <summary>Audio-thread bridge for one <see cref="VehicleSynth"/> (mono voice, replicated into every output channel).</summary>
    [AddComponentMenu("")]
    public sealed class VehicleVoice : MonoBehaviour
    {
        public VehicleSynth synth;
        public AudioSource source;
        readonly float[] mono = new float[2048];
        public volatile bool faulted;

        void OnAudioFilterRead(float[] data, int channels) { Process(data, channels); }

        /// <summary>Audio-thread entry (also callable from tests): renders the synth in mono and replicates it into every channel. After an exception the voice stays silent until the main thread rebuilds the synth and clears <see cref="faulted"/>.</summary>
        public void Process(float[] data, int channels)
        {
            var s = synth;
            if (s == null || faulted || channels <= 0) return;
            int frames = data.Length / channels;
            try
            {
                for (int o = 0; o < frames; o += mono.Length)
                {
                    int n = frames - o < mono.Length ? frames - o : mono.Length;
                    s.Render(mono, 0, n);
                    int idx = o * channels;
                    for (int i = 0; i < n; i++)
                    {
                        float v = mono[i];
                        for (int c = 0; c < channels; c++) data[idx++] = v;
                    }
                }
            }
            catch { faulted = true; System.Array.Clear(data, 0, data.Length); }
        }
    }

    /// <summary>Audio-thread bridge for the global stereo ambience (wind / rain / birds / insects).</summary>
    [AddComponentMenu("")]
    public sealed class AmbienceVoice : MonoBehaviour
    {
        public AmbienceSynth synth;
        public AmbienceParams parameters;
        public AudioSource source;
        readonly float[] left = new float[2048], right = new float[2048];
        public volatile bool faulted;

        void OnAudioFilterRead(float[] data, int channels) { Process(data, channels); }

        public void Process(float[] data, int channels)
        {
            var s = synth; var p = parameters;
            if (s == null || p == null || faulted || channels <= 0) return;
            int frames = data.Length / channels;
            try
            {
                for (int o = 0; o < frames; o += left.Length)
                {
                    int n = frames - o < left.Length ? frames - o : left.Length;
                    s.Render(p, left, right, 0, n);
                    int idx = o * channels;
                    for (int i = 0; i < n; i++)
                    {
                        if (channels == 1) { data[idx++] = 0.5f * (left[i] + right[i]); continue; }
                        data[idx] = left[i]; data[idx + 1] = right[i];
                        for (int c = 2; c < channels; c++) data[idx + c] = 0f;
                        idx += channels;
                    }
                }
            }
            catch { faulted = true; System.Array.Clear(data, 0, data.Length); }
        }
    }

    /// <summary>Audio-thread bridge for the positional river / swamp water bed.</summary>
    [AddComponentMenu("")]
    public sealed class RiverVoice : MonoBehaviour
    {
        public RiverSynth synth;
        public AudioSource source;
        public volatile float level, flow;
        readonly float[] mono = new float[2048];
        public volatile bool faulted;

        void OnAudioFilterRead(float[] data, int channels) { Process(data, channels); }

        public void Process(float[] data, int channels)
        {
            var s = synth;
            if (s == null || faulted || channels <= 0) return;
            int frames = data.Length / channels;
            try
            {
                for (int o = 0; o < frames; o += mono.Length)
                {
                    int n = frames - o < mono.Length ? frames - o : mono.Length;
                    s.Render(level, flow, mono, 0, n);
                    int idx = o * channels;
                    for (int i = 0; i < n; i++) { float v = mono[i]; for (int c = 0; c < channels; c++) data[idx++] = v; }
                }
            }
            catch { faulted = true; System.Array.Clear(data, 0, data.Length); }
        }
    }

    /// <summary>
    /// Final soft-knee limiter on the AudioListener (the whole mix): linear below 0.8, smoothly saturating towards 1.0, so the sum
    /// of several loud voices can never hard-clip the output device.
    /// </summary>
    [AddComponentMenu("")]
    public sealed class MasterLimiter : MonoBehaviour
    {
        void OnAudioFilterRead(float[] data, int channels)
        {
            for (int i = 0; i < data.Length; i++)
            {
                float x = data[i];
                if (x > 0.8f || x < -0.8f) data[i] = DspMath.MasterKnee(x);
            }
        }
    }
}

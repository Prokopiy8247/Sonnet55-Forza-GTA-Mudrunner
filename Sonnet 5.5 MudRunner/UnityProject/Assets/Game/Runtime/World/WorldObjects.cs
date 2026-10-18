using System;
using System.Collections.Generic;
using MudRunner.Vehicles;
using UnityEngine;
using UnityEngine.Rendering;

namespace MudRunner.WorldGen
{
    /// <summary>Instantiates <see cref="StructureDef"/>s as GameObjects: meshes, colliders, rigid bodies, winch anchors, sign labels, fragile bridges.</summary>
    public static class WorldObjects
    {
        public static void Kill(UnityEngine.Object o)
        {
            if (o == null) return;
            if (Application.isPlaying) UnityEngine.Object.Destroy(o); else UnityEngine.Object.DestroyImmediate(o);
        }

        public static void AddColliders(GameObject go, ColRecipe[] recipes, bool dynamic)
        {
            if (recipes == null) return;
            for (int i = 0; i < recipes.Length; i++)
            {
                var r = recipes[i];
                switch (r.shape)
                {
                    case ColShape.Box:
                        { var c = go.AddComponent<BoxCollider>(); c.center = r.center; c.size = r.size; break; }
                    case ColShape.Capsule:
                        {
                            var c = go.AddComponent<CapsuleCollider>(); c.center = r.center; c.radius = r.size.x; c.height = Mathf.Max(r.size.y, r.size.x * 2f + 0.01f); c.direction = r.axis; break;
                        }
                    case ColShape.Sphere:
                        { var c = go.AddComponent<SphereCollider>(); c.center = r.center; c.radius = r.size.x; break; }
                }
            }
        }

        public static GameObject Spawn(Transform parent, in StructureDef s, PropDef def)
        {
            var go = new GameObject(s.id);
            go.transform.SetParent(parent, false);
            go.transform.SetPositionAndRotation(s.pos, s.rot);
            go.transform.localScale = Vector3.one * (s.scale <= 0f ? 1f : s.scale);
            bool dyn = s.dynamic && def.mass > 0f;
            go.layer = dyn ? GameLayers.DynamicProps : GameLayers.Props;
            if (def.prefab != null)
            {
                var vis = UnityEngine.Object.Instantiate(def.prefab, go.transform, false);
                vis.name = "visual";
                foreach (var c in vis.GetComponentsInChildren<Collider>()) Kill(c);
            }
            else
            {
                var mf = go.AddComponent<MeshFilter>(); mf.sharedMesh = def.lods[0];
                var mr = go.AddComponent<MeshRenderer>();
                mr.sharedMaterials = def.materials;
                mr.shadowCastingMode = def.castShadows ? ShadowCastingMode.On : ShadowCastingMode.Off;
                mr.receiveShadows = true;
                if (!dyn) go.isStatic = false;
            }
            AddColliders(go, def.colliders, dyn);
            if (dyn)
            {
                var rb = go.AddComponent<Rigidbody>();
                rb.mass = def.mass * Mathf.Pow(s.scale <= 0f ? 1f : s.scale, 3f);
                rb.linearDamping = 0.02f; rb.angularDamping = 0.25f;
                rb.interpolation = RigidbodyInterpolation.None;
                rb.sleepThreshold = 0.4f;
                rb.Sleep();
            }
            if (s.anchor)
            {
                var a = go.AddComponent<WinchAnchor>();
                a.localPoint = s.anchorLocal == Vector3.zero ? new Vector3(0f, 0.9f, 0f) : s.anchorLocal;
                a.maxPull = s.anchorPull > 0f ? s.anchorPull : 1e9f;
                var pick = new GameObject("anchor_pick") { layer = GameLayers.Anchors };
                pick.transform.SetParent(go.transform, false);
                pick.transform.localPosition = a.localPoint;
                var sc = pick.AddComponent<SphereCollider>(); sc.radius = 0.55f; sc.isTrigger = true;
            }
            if (!string.IsNullOrEmpty(s.text)) SignLabel.Attach(go, s.text, s.id);
            if (!string.IsNullOrEmpty(s.tag) && s.tag.StartsWith("bridge:"))
            {
                var fb = go.AddComponent<FragileBridge>();
                string[] parts = s.tag.Substring(7).Split('|');
                fb.bridgeName = parts[0];
                float.TryParse(parts.Length > 1 ? parts[1] : "0", System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out fb.maxLoadKg);
                fb.length = def.bounds.size.z; fb.width = def.bounds.size.x;
            }
            return go;
        }

        public static int SpawnAll(Transform parent, PropSet set, IPropLibrary lib)
        {
            int n = 0;
            for (int i = 0; i < set.structures.Count; i++)
            {
                var s = set.structures[i];
                var def = lib.Get(s.id);
                if (def == null) continue;
                Spawn(parent, s, def);
                n++;
            }
            return n;
        }
    }

    /// <summary>Text label for signs (legacy TextMesh on a plaque), scaled to fit once the glyph mesh exists.</summary>
    public sealed class SignLabel : MonoBehaviour
    {
        TextMesh tm, tmBack; Transform plaque; float maxW, targetH;

        public static void Attach(GameObject sign, string text, string id)
        {
            var go = new GameObject("label");
            go.transform.SetParent(sign.transform, false);
            bool arrow = id == "sign_arrow";
            bool pole = id == "distance_pole";
            Vector3 lp = pole ? new Vector3(0f, 1.78f, 0.02f) : arrow ? new Vector3(-0.1f, 2.62f, 0.02f) : new Vector3(0f, 2.62f, 0.02f);
            go.transform.localPosition = lp;
            var lab = go.AddComponent<SignLabel>();
            lab.maxW = pole ? 0.9f : (id == "sign_arrow" || id == "sign_warn" ? 2.6f : 3.4f); lab.targetH = pole ? 0.15f : 0.26f;
            var plaque = GameObject.CreatePrimitive(PrimitiveType.Cube);
            WorldObjects.Kill(plaque.GetComponent<Collider>());
            plaque.name = "plaque"; plaque.transform.SetParent(go.transform, false);
            plaque.transform.localPosition = new Vector3(0f, 0f, 0.03f);
            plaque.GetComponent<MeshRenderer>().sharedMaterial = PropMaterials.Get("White");
            plaque.GetComponent<MeshRenderer>().shadowCastingMode = ShadowCastingMode.Off;
            lab.plaque = plaque.transform;
            var tgo = new GameObject("text");
            tgo.transform.SetParent(go.transform, false);
            tgo.transform.localPosition = new Vector3(0f, 0f, -0.01f);
            var tgoB = new GameObject("text_back");               // TextMesh is single sided: a copy on the other face
            tgoB.transform.SetParent(go.transform, false);
            tgoB.transform.localPosition = new Vector3(0f, 0f, 0.07f);
            tgoB.transform.localRotation = Quaternion.Euler(0f, 180f, 0f);
            var tmB = tgoB.AddComponent<TextMesh>();
            var tm = tgo.AddComponent<TextMesh>();
            tm.text = text; tm.anchor = TextAnchor.MiddleCenter; tm.alignment = TextAlignment.Center; tm.fontSize = 64; tm.characterSize = 0.05f;
            tm.color = new Color(0.05f, 0.05f, 0.05f);
            var font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            tmB.text = text; tmB.anchor = TextAnchor.MiddleCenter; tmB.alignment = TextAlignment.Center; tmB.fontSize = 64; tmB.characterSize = 0.05f; tmB.color = tm.color;
            if (font != null)
            {
                tm.font = font; var mr = tgo.GetComponent<MeshRenderer>(); mr.sharedMaterial = font.material; mr.shadowCastingMode = ShadowCastingMode.Off;
                tmB.font = font; var mrB = tgoB.GetComponent<MeshRenderer>(); mrB.sharedMaterial = font.material; mrB.shadowCastingMode = ShadowCastingMode.Off;
            }
            lab.tm = tm; lab.tmBack = tmB;
            // rough size estimate until the real glyph bounds are known
            float estW = Mathf.Max(0.8f, text.Length * 0.14f * 0.36f * 2f), estH = 0.26f;
            lab.ApplySize(estW, estH);
        }

        void ApplySize(float w, float h)
        {
            if (plaque != null) plaque.localScale = new Vector3(w + 0.16f, h + 0.1f, 0.04f);
        }

        void Start()
        {
            if (tm == null) return;
            var mr = tm.GetComponent<MeshRenderer>();
            if (mr == null) return;
            var b = mr.bounds;
            float w = b.size.x, h = b.size.y;
            if (w < 1e-3f || h < 1e-3f) return;
            float s = Mathf.Min(maxW / w, targetH / h);
            tm.transform.localScale = Vector3.one * s;
            if (tmBack != null) tmBack.transform.localScale = Vector3.one * s;
            ApplySize(w * s, h * s);
        }
    }

    /// <summary>
    /// Old timber bridges and the swamp causeway: they hold up to <see cref="maxLoadKg"/> (vehicle + trailer). Overloaded for about a second
    /// they collapse: the colliders disappear and the deck sags into the water.
    /// </summary>
    public sealed class FragileBridge : MonoBehaviour
    {
        public string bridgeName;
        public float maxLoadKg;
        public float length = 10f, width = 4f;
        public bool collapsed;
        public float loadKg;
        public static event Action<FragileBridge> Collapsed;

        float overTimer, fall;
        Quaternion baseRot; Vector3 basePos;

        void Start() { baseRot = transform.rotation; basePos = transform.position; }

        void FixedUpdate()
        {
            if (collapsed)
            {
                fall = Mathf.MoveTowards(fall, 1f, Time.fixedDeltaTime * 0.7f);
                float k = fall * fall;
                transform.position = basePos + Vector3.down * 2.6f * k;
                transform.rotation = baseRot * Quaternion.Euler(-5f * k, 0f, 11f * k);
                return;
            }
            if (maxLoadKg <= 0f) return;
            float m = 0f;
            var all = Vehicle.All;
            for (int i = 0; i < all.Count; i++)
            {
                var v = all[i];
                if (v == null || v.rb == null) continue;
                Vector3 l = transform.InverseTransformPoint(v.transform.position);
                if (Mathf.Abs(l.x) > width * 0.5f + 0.6f || Mathf.Abs(l.z) > length * 0.5f + 0.5f || l.y < -1.2f || l.y > 3f) continue;
                m += v.rb.mass;
                if (v.towedTrailer != null && v.towedTrailer.rb != null) m += v.towedTrailer.rb.mass;
            }
            loadKg = m;
            if (m > maxLoadKg) overTimer += Time.fixedDeltaTime; else overTimer = Mathf.Max(0f, overTimer - Time.fixedDeltaTime * 0.5f);
            if (overTimer > 1.0f) Collapse();
        }

        public void Collapse()
        {
            if (collapsed) return;
            collapsed = true;
            foreach (var c in GetComponents<Collider>()) c.enabled = false;
            Debug.Log("[MudRunner] Bridge collapsed: " + bridgeName + " (load " + loadKg.ToString("F0") + " kg > " + maxLoadKg.ToString("F0") + " kg)");
            Collapsed?.Invoke(this);
        }
    }
}

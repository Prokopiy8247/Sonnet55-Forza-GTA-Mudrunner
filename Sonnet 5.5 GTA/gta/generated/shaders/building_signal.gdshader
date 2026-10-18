shader_type spatial;
render_mode cull_back;
// Halcyon Bay: traffic-signal lens (replaces SignalRed / SignalAmber / SignalGreen). One MultiMesh instance per signal
// head set; the content manager writes the signal state into the instance custom data x every 0.25 s:
// 0 = green, 1 = yellow, 2 = red (WorldLayout.signal_state semantics).

uniform int lens = 1;                       // 1 red, 2 amber, 3 green
uniform vec4 lens_color : source_color = vec4(1.0, 0.16, 0.12, 1.0);
uniform float lit_energy = 5.0;
uniform float off_energy = 0.04;

varying flat float v_state;

void vertex() {
	v_state = INSTANCE_CUSTOM.x;
}

void fragment() {
	int st = int(v_state + 0.5);
	bool on = (lens == 1 && st == 2) || (lens == 2 && st == 1) || (lens == 3 && st == 0);
	ALBEDO = lens_color.rgb * (on ? 0.4 : 0.12);
	EMISSION = lens_color.rgb * (on ? lit_energy : off_energy);
	ROUGHNESS = 0.3;
}

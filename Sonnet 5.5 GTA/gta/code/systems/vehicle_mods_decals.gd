class_name VehicleModsDecals
extends RefCounted
## Code-generated licence plate textures (works headless and in the renderer): a tiny 5x7 bitmap font drawn into an Image.

const GLYPHS := {
	"A": ".###.|#...#|#...#|#####|#...#|#...#|#...#", "B": "####.|#...#|#...#|####.|#...#|#...#|####.",
	"C": ".####|#....|#....|#....|#....|#....|.####", "D": "####.|#...#|#...#|#...#|#...#|#...#|####.",
	"E": "#####|#....|#....|####.|#....|#....|#####", "F": "#####|#....|#....|####.|#....|#....|#....",
	"G": ".####|#....|#....|#.###|#...#|#...#|.####", "H": "#...#|#...#|#...#|#####|#...#|#...#|#...#",
	"I": ".###.|..#..|..#..|..#..|..#..|..#..|.###.", "J": "..###|...#.|...#.|...#.|...#.|#..#.|.##..",
	"K": "#...#|#..#.|#.#..|##...|#.#..|#..#.|#...#", "L": "#....|#....|#....|#....|#....|#....|#####",
	"M": "#...#|##.##|#.#.#|#.#.#|#...#|#...#|#...#", "N": "#...#|##..#|#.#.#|#..##|#...#|#...#|#...#",
	"O": ".###.|#...#|#...#|#...#|#...#|#...#|.###.", "P": "####.|#...#|#...#|####.|#....|#....|#....",
	"Q": ".###.|#...#|#...#|#...#|#.#.#|#..#.|.##.#", "R": "####.|#...#|#...#|####.|#.#..|#..#.|#...#",
	"S": ".####|#....|#....|.###.|....#|....#|####.", "T": "#####|..#..|..#..|..#..|..#..|..#..|..#..",
	"U": "#...#|#...#|#...#|#...#|#...#|#...#|.###.", "V": "#...#|#...#|#...#|#...#|#...#|.#.#.|..#..",
	"W": "#...#|#...#|#...#|#.#.#|#.#.#|##.##|#...#", "X": "#...#|#...#|.#.#.|..#..|.#.#.|#...#|#...#",
	"Y": "#...#|#...#|.#.#.|..#..|..#..|..#..|..#..", "Z": "#####|....#|...#.|..#..|.#...|#....|#####",
	"0": ".###.|#...#|#..##|#.#.#|##..#|#...#|.###.", "1": "..#..|.##..|..#..|..#..|..#..|..#..|.###.",
	"2": ".###.|#...#|....#|...#.|..#..|.#...|#####", "3": "####.|....#|....#|.###.|....#|....#|####.",
	"4": "...#.|..##.|.#.#.|#..#.|#####|...#.|...#.", "5": "#####|#....|####.|....#|....#|#...#|.###.",
	"6": "..##.|.#...|#....|####.|#...#|#...#|.###.", "7": "#####|....#|...#.|..#..|.#...|.#...|.#...",
	"8": ".###.|#...#|#...#|.###.|#...#|#...#|.###.", "9": ".###.|#...#|#...#|.####|....#|...#.|.##..",
	"-": ".....|.....|.....|#####|.....|.....|.....", " ": ".....|.....|.....|.....|.....|.....|.....",
}

const TEX_W := 256
const TEX_H := 128


static func _draw_text(img: Image, text: String, x0: int, y0: int, scale: int, color: Color, gap: int) -> int:
	var x := x0
	for ch in text.to_upper():
		var g: String = GLYPHS.get(ch, GLYPHS[" "])
		var rows := g.split("|")
		for ry in 7:
			var row: String = rows[ry]
			for rx in 5:
				if row[rx] == "#":
					img.fill_rect(Rect2i(x + rx * scale, y0 + ry * scale, scale, scale), color)
		x += 5 * scale + gap
	return x - gap - x0


static func text_width(text: String, scale: int, gap: int) -> int:
	return maxi(text.length(), 1) * (5 * scale + gap) - gap


## Plate style dictionary (VehicleModsData.PLATES entry) + registration text -> 256x128 texture.
static func plate_texture(style: Dictionary, text: String) -> ImageTexture:
	var key := "%s|%s" % [style.get("id", ""), text]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	var bg: Color = style.get("bg", Color.WHITE)
	var fg: Color = style.get("fg", Color.BLACK)
	var band: Color = style.get("band", Color(0.1, 0.3, 0.8))
	img.fill(bg)
	# border + top band
	var b := 5
	img.fill_rect(Rect2i(0, 0, TEX_W, b), fg)
	img.fill_rect(Rect2i(0, TEX_H - b, TEX_W, b), fg)
	img.fill_rect(Rect2i(0, 0, b, TEX_H), fg)
	img.fill_rect(Rect2i(TEX_W - b, 0, b, TEX_H), fg)
	img.fill_rect(Rect2i(b, b, TEX_W - 2 * b, 26), band)
	var band_text := String(style.get("band_text", ""))
	var bw := text_width(band_text, 2, 2)
	_draw_text(img, band_text, (TEX_W - bw) / 2, b + 6, 2, Color(1, 1, 1, 0.95), 2)
	# registration
	var scale := 5
	var gap := 5
	while text_width(text, scale, gap) > TEX_W - 36 and scale > 2:
		scale -= 1
		gap = maxi(scale, 2)
	var tw := text_width(text, scale, gap)
	_draw_text(img, text, (TEX_W - tw) / 2 + 2, b + 26 + (TEX_H - b * 2 - 26 - 7 * scale) / 2 + 2, scale, fg.darkened(0.0) if fg.get_luminance() > 0.5 else fg, gap)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


static var _tex_cache: Dictionary = {}

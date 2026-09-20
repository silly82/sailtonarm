#!/usr/bin/env python3
# Erzeugt store/cover-1080x540.png im selben Stil wie das App-Icon
# (icons/source/generate-icon.py): diagonaler Verlauf von Dunkelviolett nach
# Violett, weisses Schallplatten-und-Tonarm-Motiv. Braucht python3-cairo.
# Aufruf aus dem Projektverzeichnis:
#   python3 store/generate-cover.py
import math
import os

import cairo

W, H = 1080, 540
OUT_PATH = os.path.join(os.path.dirname(__file__), "cover-1080x540.png")

surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, W, H)
ctx = cairo.Context(surface)

# Gleiche Verlaufsrichtung und Farben wie das App-Icon: dunkel unten links,
# hell oben rechts.
grad = cairo.LinearGradient(0, H, W, 0)
grad.add_color_stop_rgb(0, 0x23 / 255, 0x17 / 255, 0x3B / 255)
grad.add_color_stop_rgb(1, 0x8B / 255, 0x5C / 255, 0xF6 / 255)
ctx.set_source(grad)
ctx.paint()

# -- Motiv: dasselbe wie im Icon, im 86x86-Raum gezeichnet und als Abzeichen
# links einskaliert --
badge = 360
scale = badge / 86.0
badge_x, badge_y = 90, (H - badge) / 2

ctx.save()
ctx.translate(badge_x, badge_y)
ctx.scale(scale, scale)
ctx.set_source_rgba(1, 1, 1, 0.92)

cx, cy, r = 40.0, 49.0, 22.5
ctx.set_line_width(3.0)
ctx.arc(cx, cy, r, 0, 2 * math.pi)
ctx.stroke()
ctx.set_line_width(1.6)
ctx.arc(cx, cy, r * 0.62, 0, 2 * math.pi)
ctx.stroke()
ctx.arc(cx, cy, 2.6, 0, 2 * math.pi)
ctx.fill()

pivot_x, pivot_y = 69.0, 20.0
head_x, head_y = 44.0, 41.0
ctx.arc(pivot_x, pivot_y, 4.6, 0, 2 * math.pi)
ctx.fill()
ctx.set_line_width(3.2)
ctx.set_line_cap(cairo.LINE_CAP_ROUND)
ctx.move_to(pivot_x, pivot_y)
ctx.line_to(head_x, head_y)
ctx.stroke()

angle = math.atan2(head_y - pivot_y, head_x - pivot_x)
ctx.save()
ctx.translate(head_x, head_y)
ctx.rotate(angle)
ctx.rectangle(-4.0, -3.4, 8.0, 6.8)
ctx.fill()
ctx.restore()
ctx.restore()

# -- Titel und Untertitel rechts neben dem Abzeichen --
text_x = badge_x + badge + 55

ctx.set_source_rgb(1, 1, 1)
ctx.select_font_face("Noto Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
ctx.set_font_size(96)
title_baseline_y = H / 2 - 10
ctx.move_to(text_x, title_baseline_y)
ctx.show_text("Tonarm")

ctx.set_source_rgba(1, 1, 1, 0.85)
ctx.select_font_face("Noto Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
ctx.set_font_size(34)
ctx.move_to(text_x, title_baseline_y + 55)
ctx.show_text("Music Assistant für SailfishOS")

surface.write_to_png(OUT_PATH)
print(OUT_PATH)

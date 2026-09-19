#!/usr/bin/env python3
# Erzeugt icons/<size>x<size>/harbour-tonarm.png neu.
# Braucht python3-cairo (pycairo). Aufruf aus dem Projektverzeichnis:
#   python3 icons/source/generate-icon.py
#
# Motiv: Schallplatte mit Tonarm. Alles im 86x86-Raum gezeichnet und für die
# anderen Grössen hochskaliert -- die Silhouette stammt aus Jollas offizieller
# icon-launcher-template.svg, damit der Umriss zu den Systemicons passt.
import math
import os

import cairo

SIZES = [86, 108, 128, 172]
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "icons")


def sailfish_silhouette(ctx):
    """Der organische Sailfish-Umriss, exakter Pfad aus der Vorlage (86x86)."""
    ctx.move_to(84.277, 0.3)
    ctx.line_to(43, 0.3)
    ctx.curve_to(19.417, 0.3, 0.3, 19.418, 0.3, 43)
    ctx.line_to(0.3, 84.277)
    ctx.curve_to(0.3, 85.063, 0.937, 85.7, 1.723, 85.7)
    ctx.line_to(43, 85.7)
    ctx.curve_to(66.583, 85.7, 85.7, 66.582, 85.7, 43)
    ctx.line_to(85.7, 1.723)
    ctx.curve_to(85.7, 0.937, 85.063, 0.3, 84.277, 0.3)
    ctx.close_path()


def draw(size):
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    ctx = cairo.Context(surface)
    ctx.scale(size / 86.0, size / 86.0)

    sailfish_silhouette(ctx)
    grad = cairo.LinearGradient(0.7169, 85.2831, 85.2831, 0.7169)
    grad.add_color_stop_rgb(0, 0x23 / 255, 0x17 / 255, 0x3B / 255)
    grad.add_color_stop_rgb(1, 0x8B / 255, 0x5C / 255, 0xF6 / 255)
    ctx.set_source(grad)
    ctx.fill()

    ctx.set_source_rgb(1, 1, 1)

    # Platte: zwei Rillen als Ringe, dazu das Mittelloch ausgespart.
    cx, cy, r = 40.0, 49.0, 22.5
    ctx.set_line_width(3.0)
    ctx.arc(cx, cy, r, 0, 2 * math.pi)
    ctx.stroke()
    ctx.set_line_width(1.6)
    ctx.arc(cx, cy, r * 0.62, 0, 2 * math.pi)
    ctx.stroke()
    ctx.arc(cx, cy, 2.6, 0, 2 * math.pi)
    ctx.fill()

    # Tonarm: Drehpunkt oben rechts, Rohr schräg zur Platte, Tonabnehmer am Ende.
    pivot_x, pivot_y = 69.0, 20.0
    head_x, head_y = 44.0, 41.0
    ctx.arc(pivot_x, pivot_y, 4.6, 0, 2 * math.pi)
    ctx.fill()

    ctx.set_line_width(3.2)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    ctx.move_to(pivot_x, pivot_y)
    ctx.line_to(head_x, head_y)
    ctx.stroke()

    # Tonabnehmer: kleines Rechteck quer zum Rohr.
    angle = math.atan2(head_y - pivot_y, head_x - pivot_x)
    ctx.save()
    ctx.translate(head_x, head_y)
    ctx.rotate(angle)
    ctx.rectangle(-4.0, -3.4, 8.0, 6.8)
    ctx.fill()
    ctx.restore()

    out_path = os.path.join(OUT_DIR, "%dx%d" % (size, size), "harbour-tonarm.png")
    surface.write_to_png(out_path)
    print(out_path)


if __name__ == "__main__":
    for s in SIZES:
        draw(s)

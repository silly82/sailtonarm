#!/usr/bin/env python3
# Erzeugt icons/<size>x<size>/harbour-tonarm.png neu.
# Braucht python3-cairo (pycairo). Aufruf aus dem Projektverzeichnis:
#   python3 icons/source/generate-icon.py
#
# Motiv: Schallplatte mit Tonarm. Alles im 86x86-Raum gezeichnet und für die
# anderen Grössen hochskaliert. Umriss: ein Tropfen, nur oben rechts eckig;
# die Platte liegt konzentrisch in der Rundung, der Tonarm-Drehpunkt in der
# spitzen Ecke.
import math
import os

import cairo

SIZES = [86, 108, 128, 172]
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "icons")
STORE_ICON = os.path.join(os.path.dirname(__file__), "..", "..", "store", "icon-172x172.png")

# Mittelpunkt und Radius der Rundung; die Platte sitzt genau darin.
CX, CY, R_OUTER = 43.0, 43.0, 42.7


def sailfish_silhouette(ctx):
    """Tropfen: drei Ecken voll gerundet (ein Kreis um die Mitte), nur oben
    rechts eine spitze Ecke."""
    ctx.move_to(85.7, 0.3)
    ctx.line_to(CX, 0.3)
    ctx.arc_negative(CX, CY, R_OUTER, -math.pi / 2, 0)
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

    # Platte: konzentrisch in der Rundung, zwei Rillen als Ringe, dazu das
    # Mittelloch.
    r = 25.0
    ctx.set_line_width(3.0)
    ctx.arc(CX, CY, r, 0, 2 * math.pi)
    ctx.stroke()
    ctx.set_line_width(1.6)
    ctx.arc(CX, CY, r * 0.6, 0, 2 * math.pi)
    ctx.stroke()
    ctx.arc(CX, CY, 2.6, 0, 2 * math.pi)
    ctx.fill()

    # Tonarm: Drehpunkt in der spitzen Ecke, Nadel in den Rillen der Platte.
    pivot_x, pivot_y = 72.0, 14.0
    head_x, head_y = 58.0, 31.5
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
    if size == 172:
        surface.write_to_png(STORE_ICON)
        print(STORE_ICON)


if __name__ == "__main__":
    for s in SIZES:
        draw(s)

"""Render original geometry as SVG and vector PDF for authoring review."""
from pathlib import Path
from xml.sax.saxutils import escape
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
from geometry import GROUPS
from paths import commands

out=Path('/private/tmp/mivu-pip-art')
out.mkdir(exist_ok=True)
svg=['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">']
c=canvas.Canvas(str(out/'pip-master.pdf'),pagesize=(512,512))
c.translate(0,512);c.scale(1,-1)
for group in GROUPS:
    svg.append(f'<g id="{group.name}">')
    for s in group.shapes:
        svg.append(f'<path d="{s.path}" fill="{s.color}" stroke="{s.stroke or "none"}" stroke-width="{s.width}" stroke-linecap="round" stroke-linejoin="round"/>')
        p=c.beginPath()
        for op,v in commands(s.path):
            if op=='M':p.moveTo(*v)
            elif op=='L':p.lineTo(*v)
            elif op=='C':p.curveTo(*v)
            else:p.close()
        if s.color!='none':c.setFillColor(HexColor(s.color))
        if s.stroke:c.setStrokeColor(HexColor(s.stroke));c.setLineWidth(s.width)
        c.setLineCap(1);c.setLineJoin(1)
        c.drawPath(p,fill=s.color!='none',stroke=s.stroke is not None)
    svg.append('</g>')
svg.append('</svg>')
(out/'pip-master.svg').write_text('\n'.join(svg))
c.save()
print(out)

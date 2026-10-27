#!/usr/bin/env python3
"""xml_to_md.py — convierte la referencia de clases de rclgd (doc_classes/*.xml,
formato class.xsd de Godot) en Markdown compacto para que una IA la lea.

Uso:
    xml_to_md.py <rclgd>/rclgd/doc_classes <salida_dir> [--ref "<rama>@<commit>"]

Genera un .md por clase y un INDEX.md. Es la misma fuente que usa
docs/make_rst.py de rclgd para la web de readthedocs, así que el contenido es
el oficial; solo cambia el formato. Regenerar cuando cambie la versión de rclgd.
"""
import pathlib
import re
import sys
import xml.etree.ElementTree as ET


def bb(text: str) -> str:
    """BBCode de la doc de Godot -> Markdown."""
    if not text:
        return ""
    t = text.strip()
    # Bloques de código primero (pueden contener corchetes).
    t = re.sub(r"\[codeblocks?\](.*?)\[/codeblocks?\]",
               lambda m: "\n```gdscript\n" + _dedent(m.group(1)) + "\n```\n", t, flags=re.S)
    t = re.sub(r"\[gdscript[^\]]*\](.*?)\[/gdscript\]", lambda m: _dedent(m.group(1)), t, flags=re.S)
    t = re.sub(r"\[code\](.*?)\[/code\]", r"`\1`", t, flags=re.S)
    t = re.sub(r"\[b\](.*?)\[/b\]", r"**\1**", t, flags=re.S)
    t = re.sub(r"\[i\](.*?)\[/i\]", r"*\1*", t, flags=re.S)
    t = re.sub(r"\[url=([^\]]+)\](.*?)\[/url\]", r"[\2](\1)", t, flags=re.S)
    t = re.sub(r"\[(method|member|signal|constant|enum|param|annotation|theme_item) ([^\]]+)\]", r"`\2`", t)
    t = re.sub(r"\[([A-Z][A-Za-z0-9_]*)\]", r"`\1`", t)  # [RosMsg], [Node]...
    t = t.replace("[br]", "\n")
    lines = [ln.strip() if not ln.startswith("    ") else ln for ln in t.splitlines()]
    out, in_code = [], False
    for ln in lines:
        if ln.startswith("```"):
            in_code = not in_code
        out.append(ln)
    return "\n".join(out).strip()


def _dedent(code: str) -> str:
    rows = [r.replace("\t", "    ") for r in code.strip("\n").splitlines()]
    pad = min((len(r) - len(r.lstrip()) for r in rows if r.strip()), default=0)
    return "\n".join(r[pad:] for r in rows)


def sig(m) -> str:
    ret = m.find("return")
    rtype = ret.get("type") if ret is not None else "void"
    if ret is not None and ret.get("enum"):
        rtype = ret.get("enum")
    params = []
    for p in sorted(m.findall("param"), key=lambda x: int(x.get("index", 0))):
        s = f"{p.get('name')}: {p.get('enum') or p.get('type')}"
        if p.get("default") is not None:
            s += f" = {p.get('default')}"
        params.append(s)
    q = m.get("qualifiers")
    return f"{m.get('name')}({', '.join(params)}) -> {rtype}`" + (f" *({q})*" if q else "")


def convert(xml_path: pathlib.Path) -> tuple[str, str, str]:
    root = ET.parse(xml_path).getroot()
    name, inherits = root.get("name"), root.get("inherits", "")
    brief = bb(root.findtext("brief_description", ""))
    md = [f"# {name}", "", f"Hereda de: `{inherits}`", "", brief, "", bb(root.findtext("description", "")), ""]
    sections = [("methods", "method", "Métodos"), ("signals", "signal", "Señales")]
    for tag, item, title in sections:
        items = root.find(tag)
        if items is None or not list(items):
            continue
        md += [f"## {title}", ""]
        for m in items.findall(item):
            md += [f"### `{sig(m)}", "", bb(m.findtext("description", "")), ""]
    members = root.find("members")
    if members is not None and list(members):
        md += ["## Propiedades", ""]
        for m in members.findall("member"):
            d = f" = {m.get('default')}" if m.get("default") is not None else ""
            md += [f"### `{m.get('name')}: {m.get('enum') or m.get('type')}{d}`", "", bb(m.text or ""), ""]
    consts = root.find("constants")
    if consts is not None and list(consts):
        md += ["## Constantes", ""]
        for c in consts.findall("constant"):
            enum = f" (enum `{c.get('enum')}`)" if c.get("enum") else ""
            md += [f"- `{c.get('name')} = {c.get('value')}`{enum} — {bb(c.text or '').replace(chr(10), ' ')}"]
        md.append("")
    return name, brief.replace("\n", " "), "\n".join(md).rstrip() + "\n"


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    ref = sys.argv[sys.argv.index("--ref") + 1] if "--ref" in sys.argv else "desconocida"
    dst.mkdir(parents=True, exist_ok=True)
    index = ["# Referencia de clases de rclgd (generada)", "",
             f"Fuente: `rclgd/doc_classes/*.xml` de **{ref}**. Generado con `skills/rclgd/scripts/xml_to_md.py`;",
             "no editar a mano: regenerar al cambiar de versión.", "", "| Clase | Resumen |", "|---|---|"]
    for x in sorted(src.glob("*.xml")):
        name, brief, md = convert(x)
        (dst / f"{name}.md").write_text(md, encoding="utf-8")
        index.append(f"| [{name}]({name}.md) | {brief} |")
    (dst / "INDEX.md").write_text("\n".join(index) + "\n", encoding="utf-8")
    print(f"{len(index) - 7} clases -> {dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

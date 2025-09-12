#!/usr/bin/env python3

import argparse
import html
import os
from pathlib import Path
import shutil
import sys
from typing import Dict


def parse_name_path(arg: str) -> (str, Path):
    if "=" not in arg:
        raise argparse.ArgumentTypeError(f"Expected NAME=PATH, got: {arg}")
    name, path = arg.split("=", 1)
    name = name.strip()
    p = Path(path).expanduser().resolve()
    if not name:
        raise argparse.ArgumentTypeError(f"Empty name in mapping: {arg}")
    if not p.exists():
        raise argparse.ArgumentTypeError(f"Path does not exist: {p}")
    if not p.is_dir():
        raise argparse.ArgumentTypeError(f"Path is not a directory: {p}")
    return name, p


def discover_reports(root: Path) -> Dict[str, Path]:
    """
    Recursively discover report directories under root.

    A report directory is any directory (except root itself) that contains an
    index.html file (unless require_index=False). The mapping key is the
    POSIX-style relative path from root (e.g. "modelA/part1").
    """
    reports: Dict[str, Path] = {}
    root = root.resolve()

    for dirpath, dirnames, filenames in os.walk(root):
        print(f"Checking {dirpath}")
        current = Path(dirpath)
        if current == root:
            continue  # skip the root itself
        has_index = "index.html" in filenames
        if not has_index:
            continue
        rel = current.relative_to(root).as_posix()
        reports[rel] = current
    return reports


def write_index(site_dir: Path, title: str, reports: Dict[str, Path]) -> None:
    links = "\n".join(
        f'          <li><a href="{html.escape(name)}/index.html">{html.escape(name)}</a></li>'
        for name in sorted(reports.keys())
    )
    html_doc = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)}</title>
  <style>
    body {{ font-family: system-ui, -apple-system, Segoe UI, Roboto, sans-serif; margin: 2rem; }}
    h1 {{ margin-bottom: 0.5rem; }}
    ul {{ line-height: 1.8; }}
  </style>
</head>
<body>
  <h1>{html.escape(title)}</h1>
  <p>Select a report:</p>
  <ul>
{links}
  </ul>
</body>
</html>
"""
    (site_dir / "index.html").write_text(html_doc, encoding="utf-8")


def assemble_site(site: Path, reports: Dict[str, Path], title: str, clean: bool) -> None:
    if clean and site.exists():
        shutil.rmtree(site)
    site.mkdir(parents=True, exist_ok=True)
    (site / ".nojekyll").touch()

    for name, src in reports.items():
        dst = site / name
        # Copy contents of src into dst (merge if exists)
        shutil.copytree(src, dst, dirs_exist_ok=True, symlinks=True, copy_function=shutil.copy2)

    write_index(site, title, reports)

    gha_out = os.environ.get("GITHUB_OUTPUT")
    if gha_out:
        with open(gha_out, "a", encoding="utf-8") as f:
            f.write(f"path={site}\n")


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="Assemble multiple coverage HTML reports into a single site.")
    p.add_argument("--site", default="coverage-site", help="Output site directory (default: coverage-site)")
    p.add_argument("--title", default="Coverage Reports", help="Site title (default: Coverage Reports)")
    p.add_argument("--clean", action="store_true", help="Clean the site directory before assembling")
    p.add_argument(
        "--auto-from",
        type=Path,
        help="Discover reports from subdirectories of this directory (uses subdir names; requires index.html)",
    )
    p.add_argument(
        "mappings",
        nargs="*",
        help="Explicit report mappings as NAME=PATH (e.g., double_gyre=./coverage-html)",
    )
    args = p.parse_args(argv)

    reports: Dict[str, Path] = {}

    # Add discovered reports
    if args.auto_from:
        root = args.auto_from.expanduser().resolve()
        if not root.is_dir():
            p.error(f"--auto-from path is not a directory: {root}")
        reports.update(discover_reports(root))

    # Add explicit mappings (these override discovery if names collide)
    for m in args.mappings:
        name, path = parse_name_path(m)
        reports[name] = path

    if not reports:
        p.error("No reports provided. Use --auto-from or NAME=PATH mappings.")

    site_dir = Path(args.site).expanduser().resolve()
    print(f"Assembling {len(reports)} reports into site: {site_dir}")
    assemble_site(site_dir, reports, args.title, args.clean)
    return 0


if __name__ == "__main__":
    sys.exit(main())

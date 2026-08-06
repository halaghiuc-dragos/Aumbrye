"""Write Godot 4 text ArrayMesh resources (.mesh / .tres)."""

from __future__ import annotations

from pathlib import Path

from mesh_builder import MeshData


def _aabb(mesh: MeshData) -> tuple[float, float, float, float, float, float]:
    if not mesh.vertices:
        return (0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    xs = [v[0] for v in mesh.vertices]
    ys = [v[1] for v in mesh.vertices]
    zs = [v[2] for v in mesh.vertices]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    min_z, max_z = min(zs), max(zs)
    return (min_x, min_y, min_z, max_x - min_x, max_y - min_y, max_z - min_z)


def _fmt_vec3_array(vectors: list[tuple[float, float, float]]) -> str:
    parts = [f"{v:.6g}" for triple in vectors for v in triple]
    return "PackedVector3Array(" + ", ".join(parts) + ")"


def _fmt_color_array(colors: list[tuple[float, float, float]]) -> str:
    parts = [f"{c:.6g}" for triple in colors for c in (triple[0], triple[1], triple[2], 1.0)]
    return "PackedColorArray(" + ", ".join(parts) + ")"


def _fmt_index_array(indices: list[int]) -> str:
    return "PackedInt32Array(" + ", ".join(str(i) for i in indices) + ")"


def write_mesh(path: Path, mesh: MeshData) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    ax, ay, az, sx, sy, sz = _aabb(mesh)
    arrays = [
        _fmt_vec3_array(mesh.vertices),
        _fmt_vec3_array(mesh.normals),
        "null",
        _fmt_color_array(mesh.colors),
        "null",
        "null",
        "null",
        "null",
        "null",
        "null",
        "null",
        "null",
        "null",
        _fmt_index_array(mesh.indices),
    ]
    arrays_block = ",\n".join(f"\t{line}" for line in arrays)
    content = (
        "[gd_resource type=\"ArrayMesh\" format=3]\n\n"
        "[resource]\n"
        "_surfaces = [{\n"
        f'"aabb": AABB({ax:.6g}, {ay:.6g}, {az:.6g}, {sx:.6g}, {sy:.6g}, {sz:.6g}),\n'
        '"format": 0,\n'
        '"primitive": 4,\n'
        '"arrays": [\n'
        f"{arrays_block}\n"
        "]\n"
        "}]\n"
    )
    path.write_text(content, encoding="utf-8", newline="\n")


def mesh_resource_path(archetype_id: str, part_name: str) -> str:
    return f"res://assets/characters/{archetype_id}/{part_name}.mesh"

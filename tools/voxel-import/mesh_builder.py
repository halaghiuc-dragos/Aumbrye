"""Greedy meshing with interior culling and vertex colours."""

from __future__ import annotations

from dataclasses import dataclass

from palette import RGB, snap_colour
from vox_io import VoxelModel

EDGE = 0.04


@dataclass
class MeshData:
    vertices: list[tuple[float, float, float]]
    normals: list[tuple[float, float, float]]
    colors: list[tuple[float, float, float]]
    indices: list[int]

    def triangle_count(self) -> int:
        return len(self.indices) // 3


def _voxel_colour(model: VoxelModel, index: int) -> RGB:
    if index <= 0 or index >= len(model.palette):
        return (1.0, 0.0, 1.0)
    return snap_colour(model.palette[index])


def mesh_model(model: VoxelModel) -> MeshData:
    voxels = model.voxels
    if not voxels:
        return MeshData([], [], [], [])

    vertices: list[tuple[float, float, float]] = []
    normals: list[tuple[float, float, float]] = []
    colors: list[tuple[float, float, float]] = []
    indices: list[int] = []

    def emit_quad(
        corners: list[tuple[float, float, float]],
        normal: tuple[float, float, float],
        colour: RGB,
    ) -> None:
        base = len(vertices)
        for corner in corners:
            vertices.append(corner)
            normals.append(normal)
            colors.append(colour)
        indices.extend([base, base + 1, base + 2, base, base + 2, base + 3])

    coords = list(voxels.keys())
    mins = [min(c[i] for c in coords) for i in range(3)]
    maxs = [max(c[i] for c in coords) + 1 for i in range(3)]
    dims = [maxs[i] - mins[i] for i in range(3)]

    for axis in range(3):
        u_axis = (axis + 1) % 3
        v_axis = (axis + 2) % 3
        for direction in (-1, 1):
            normal = [0.0, 0.0, 0.0]
            normal[axis] = float(direction)
            normal_t = (normal[0], normal[1], normal[2])

            for d in range(dims[axis]):
                mask: dict[tuple[int, int], RGB] = {}
                for u in range(dims[u_axis]):
                    for v in range(dims[v_axis]):
                        pos = [0, 0, 0]
                        pos[axis] = mins[axis] + d + (1 if direction > 0 else 0)
                        pos[u_axis] = mins[u_axis] + u
                        pos[v_axis] = mins[v_axis] + v
                        key = (pos[0], pos[1], pos[2])
                        if key not in voxels:
                            continue
                        neighbor = list(pos)
                        neighbor[axis] += direction
                        nkey = (neighbor[0], neighbor[1], neighbor[2])
                        if nkey in voxels:
                            continue
                        mask[(u, v)] = _voxel_colour(model, voxels[key])

                consumed: set[tuple[int, int]] = set()
                for u in range(dims[u_axis]):
                    for v in range(dims[v_axis]):
                        if (u, v) in consumed or (u, v) not in mask:
                            continue
                        colour = mask[(u, v)]
                        width = 1
                        while (
                            (u + width, v) in mask
                            and (u + width, v) not in consumed
                            and mask[(u + width, v)] == colour
                        ):
                            width += 1
                        height = 1
                        grow = True
                        while grow and v + height < dims[v_axis]:
                            for du in range(width):
                                cell = (u + du, v + height)
                                if cell in consumed or cell not in mask or mask[cell] != colour:
                                    grow = False
                                    break
                            if grow:
                                height += 1
                        for du in range(width):
                            for dv in range(height):
                                consumed.add((u + du, v + dv))

                        def corner_at(cu: int, cv: int) -> tuple[float, float, float]:
                            pos = [0.0, 0.0, 0.0]
                            pos[axis] = float(mins[axis] + d + (1 if direction > 0 else 0))
                            pos[u_axis] = float(mins[u_axis] + cu)
                            pos[v_axis] = float(mins[v_axis] + cv)
                            return (pos[0] * EDGE, pos[1] * EDGE, pos[2] * EDGE)

                        c0 = corner_at(u, v)
                        c1 = corner_at(u + width, v)
                        c2 = corner_at(u + width, v + height)
                        c3 = corner_at(u, v + height)
                        if direction > 0:
                            emit_quad([c0, c1, c2, c3], normal_t, colour)
                        else:
                            emit_quad([c0, c3, c2, c1], normal_t, colour)

    return MeshData(vertices=vertices, normals=normals, colors=colors, indices=indices)


def validate_mesh_on_grid(mesh: MeshData) -> None:
    for vx, vy, vz in mesh.vertices:
        for value in (vx, vy, vz):
            snapped = round(value / EDGE) * EDGE
            if abs(value - snapped) > 1e-4:
                raise ValueError(f"vertex {value} not on grid")

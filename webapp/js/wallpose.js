// Pose for putting a fixture flat on a wall, ported from WallPose in
// Kabelmeter/Core/PlacementSession.swift. Returns a column-major 4x4 matrix
// (as WebXR and three.js use) with +Z out of the wall towards the camera and
// +Y up along the wall, or null when the surface is a floor or ceiling.

const MAX_NORMAL_Y = 0.7;

export function wallPose(position, normal, camera, offset = 0.0005) {
  let z = normalize(normal);
  if (!z) return null;
  const toCamera = sub(camera, position);
  if (dot(z, toCamera) < 0) z = scale(z, -1);
  if (Math.abs(z.y) > MAX_NORMAL_Y) return null;
  const up = { x: 0, y: 1, z: 0 };
  const y = normalize(sub(up, scale(z, dot(up, z))));
  const x = cross(y, z);
  const p = add(position, scale(z, offset));
  return [x.x, x.y, x.z, 0, y.x, y.y, y.z, 0, z.x, z.y, z.z, 0, p.x, p.y, p.z, 1];
}

const add = (a, b) => ({ x: a.x + b.x, y: a.y + b.y, z: a.z + b.z });
const sub = (a, b) => ({ x: a.x - b.x, y: a.y - b.y, z: a.z - b.z });
const scale = (a, s) => ({ x: a.x * s, y: a.y * s, z: a.z * s });
const dot = (a, b) => a.x * b.x + a.y * b.y + a.z * b.z;
const cross = (a, b) => ({ x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x });

function normalize(a) {
  const len = Math.hypot(a.x, a.y, a.z);
  return len > 1e-6 ? scale(a, 1 / len) : null;
}

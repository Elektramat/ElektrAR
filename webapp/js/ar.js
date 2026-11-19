// Live AR with WebXR (Chrome on Android with ARCore). iPhone Safari has no WebXR;
// app.js falls back to manual input and AR Quick Look there.
//
// One session does both modes: measuring (points on any surface, live preview segment)
// and placing fixtures on walls. Placed fixtures get a WebXR anchor when the browser
// supports it, so they stay put while ARCore refines its map. They do not survive a
// reload: browsers cannot save and recognise a room the way ARKit's world map can.

import { wallPose } from './wallpose.js';
import { pathLength } from './pricing.js';

const THREE_URL = 'https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.js';

export async function isARSupported() {
  try {
    return Boolean(navigator.xr) && (await navigator.xr.isSessionSupported('immersive-ar'));
  } catch {
    return false;
  }
}

const COLOURS = {
  studiowit: 0xf2f2ee, 'studiowit-mat': 0xebebe6, alpinwit: 0xf5f5f1, 'zuiver-wit': 0xfafafa,
  creme: 0xeee4cb, ivoorwit: 0xefe7d3, 'zwart-mat': 0x232323, 'mat-zwart': 0x232323,
  antraciet: 0x3b3c3e, aluzilver: 0xb9babc,
};

/** Frame colour: exact match, else the insert colour (last part, e.g. "witglas-studiowit"). */
function colourOf(fixture) {
  return COLOURS[fixture.colour] ?? COLOURS[fixture.colour.split('-').pop()] ?? 0xf2f2ee;
}

/**
 * Starts an AR session. `getMode()` returns "measure" or "place", `getFixture()` the
 * selected fixture. `onFrame(state)` gets { length, confirmed, points, canAdd, canPlace, message }
 * about 10 times per second. Returns a controller, or throws when the session fails.
 */
export async function startAR({ overlay, getMode, getFixture, onFrame, onEnd }) {
  const THREE = await import(THREE_URL);
  const session = await navigator.xr.requestSession('immersive-ar', {
    requiredFeatures: ['hit-test'],
    optionalFeatures: ['dom-overlay', 'anchors'],
    domOverlay: { root: overlay },
  });

  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
  renderer.setPixelRatio(window.devicePixelRatio);
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.xr.enabled = true;
  renderer.xr.setReferenceSpaceType('local');
  renderer.domElement.className = 'xr-canvas';
  document.body.appendChild(renderer.domElement);
  await renderer.xr.setSession(session);

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera();
  scene.add(new THREE.HemisphereLight(0xffffff, 0x777777, 2.2));
  const sun = new THREE.DirectionalLight(0xffffff, 1.4);
  sun.position.set(0.4, 1, 0.8);
  scene.add(sun);

  const refSpace = renderer.xr.getReferenceSpace();
  const viewerSpace = await session.requestReferenceSpace('viewer');
  const hitSource = await session.requestHitTestSource({ space: viewerSpace });

  const cableColour = new THREE.MeshBasicMaterial({ color: 0x34bbda }); // secondary: cables in AR
  const preview = new THREE.MeshBasicMaterial({ color: 0x34bbda, transparent: true, opacity: 0.6 });
  const white = new THREE.MeshBasicMaterial({ color: 0xffffff });
  const segmentGeometry = new THREE.BoxGeometry(0.004, 1, 0.004);
  const dotGeometry = new THREE.SphereGeometry(0.008, 16, 12);

  const reticle = new THREE.Mesh(new THREE.RingGeometry(0.03, 0.04, 32).rotateX(-Math.PI / 2), white);
  reticle.matrixAutoUpdate = false;
  reticle.visible = false;
  scene.add(reticle);
  const previewSegment = new THREE.Mesh(segmentGeometry, preview);
  previewSegment.visible = false;
  scene.add(previewSegment);

  const points = [];
  const pointMeshes = [];
  const placed = []; // { group, anchor }
  const pendingAnchors = [];
  let ghost = null;
  let ghostFixtureId = null;
  let lastHit = null; // { position, matrix }
  let lastPose = null; // wall pose for placing
  let lastReport = 0;

  function placeSegment(mesh, a, b) {
    const d = new THREE.Vector3().subVectors(b, a);
    const length = d.length();
    if (length < 1e-4) return;
    mesh.position.copy(a).addScaledVector(d, 0.5);
    mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), d.normalize());
    mesh.scale.set(1, length, 1);
  }

  function fixtureMesh(fixture, opacity = 1) {
    const [w, h] = (fixture.frameMM ?? [80, 80]).map((v) => v / 1000);
    const depth = (fixture.depthMM ?? 12) / 1000;
    const transparent = opacity < 1;
    const frame = new THREE.MeshStandardMaterial({ color: colourOf(fixture), roughness: 0.5, transparent, opacity });
    const insert = new THREE.MeshStandardMaterial({ color: colourOf(fixture), roughness: 0.35, transparent, opacity });
    const group = new THREE.Group();
    const plate = new THREE.Mesh(new THREE.BoxGeometry(w, h, depth * 0.55), frame);
    plate.position.z = depth * 0.275; // back of the plate on the wall (z = 0), +Z out of the wall
    group.add(plate);
    const inner = w * 0.68;
    if (fixture.product === 'stopcontact') {
      const cup = new THREE.Mesh(new THREE.CylinderGeometry(inner * 0.42, inner * 0.42, depth * 0.5, 40).rotateX(Math.PI / 2), insert);
      cup.position.z = depth * 0.6;
      group.add(cup);
      const holeMaterial = new THREE.MeshBasicMaterial({ color: 0x111111, transparent, opacity });
      for (const x of [-0.0095, 0.0095]) {
        const hole = new THREE.Mesh(new THREE.CircleGeometry(0.0024, 16), holeMaterial);
        hole.position.set(x, 0, depth * 0.851);
        group.add(hole);
      }
    } else {
      const rocker = new THREE.Mesh(new THREE.BoxGeometry(inner, inner, depth * 0.45), insert);
      rocker.position.z = depth * 0.75;
      group.add(rocker);
    }
    group.matrixAutoUpdate = false;
    return group;
  }

  function updateGhost(fixture, pose) {
    if (fixture?.id !== ghostFixtureId) {
      if (ghost) scene.remove(ghost);
      ghost = fixture ? fixtureMesh(fixture, 0.55) : null;
      ghostFixtureId = fixture?.id ?? null;
      if (ghost) scene.add(ghost);
    }
    if (!ghost) return;
    ghost.visible = Boolean(pose);
    if (pose) ghost.matrix.fromArray(pose);
  }

  function totalLength() {
    const confirmed = pathLength(points);
    if (getMode() !== 'measure' || !lastHit || points.length === 0) return confirmed;
    return confirmed + points[points.length - 1].distanceTo(lastHit.position);
  }

  renderer.setAnimationLoop((time, frame) => {
    if (!frame) return;
    const mode = getMode();
    const hits = frame.getHitTestResults(hitSource);
    const pose = hits.length ? hits[0].getPose(refSpace) : null;
    lastHit = pose
      ? { position: new THREE.Vector3(pose.transform.position.x, pose.transform.position.y, pose.transform.position.z), matrix: pose.transform.matrix }
      : null;

    const viewer = frame.getViewerPose(refSpace);
    lastPose = null;
    if (mode === 'place' && lastHit && viewer) {
      const m = lastHit.matrix; // column-major; column 1 is the surface normal
      lastPose = wallPose(lastHit.position, { x: m[4], y: m[5], z: m[6] }, viewer.transform.position);
    }

    reticle.visible = mode === 'measure' && Boolean(lastHit);
    if (reticle.visible) reticle.matrix.fromArray(lastHit.matrix);
    previewSegment.visible = mode === 'measure' && Boolean(lastHit) && points.length > 0;
    if (previewSegment.visible) placeSegment(previewSegment, points[points.length - 1], lastHit.position);
    updateGhost(mode === 'place' ? getFixture() : null, lastPose);

    // Anchors can only be created inside a frame callback.
    while (pendingAnchors.length) {
      const item = pendingAnchors.shift();
      if (!frame.createAnchor) break;
      const m = new THREE.Matrix4().fromArray(item.pose);
      const p = new THREE.Vector3();
      const q = new THREE.Quaternion();
      m.decompose(p, q, new THREE.Vector3());
      frame.createAnchor(new XRRigidTransform(p, q), refSpace)
        .then((anchor) => { if (placed.includes(item)) item.anchor = anchor; else anchor.delete(); })
        .catch(() => {});
    }
    for (const item of placed) {
      if (!item.anchor || !frame.trackedAnchors?.has(item.anchor)) continue;
      const anchorPose = frame.getPose(item.anchor.anchorSpace, refSpace);
      if (anchorPose) item.group.matrix.fromArray(anchorPose.transform.matrix);
    }

    renderer.render(scene, camera);

    if (time - lastReport > 100) {
      lastReport = time;
      let message = null;
      if (!lastHit) message = mode === 'place' ? 'Richt op een muur' : 'Richt op een muur of vloer en beweeg langzaam';
      else if (mode === 'place' && !lastPose) message = 'Richt op een muur, niet op de vloer';
      onFrame({ length: totalLength(), confirmed: pathLength(points), points: points.length, canAdd: Boolean(lastHit), canPlace: Boolean(lastPose), message });
    }
  });

  session.addEventListener('end', () => {
    renderer.setAnimationLoop(null);
    hitSource.cancel?.();
    renderer.domElement.remove();
    renderer.dispose();
    onEnd?.();
  });

  return {
    addPoint() {
      if (!lastHit || getMode() !== 'measure') return false;
      const p = lastHit.position.clone();
      if (points.length) {
        const seg = new THREE.Mesh(segmentGeometry, cableColour);
        placeSegment(seg, points[points.length - 1], p);
        scene.add(seg);
        pointMeshes.push(seg);
      }
      const dot = new THREE.Mesh(dotGeometry, white);
      dot.position.copy(p);
      scene.add(dot);
      pointMeshes.push(dot);
      points.push(p);
      return true;
    },
    undoPoint() {
      if (!points.length) return;
      points.pop();
      const remove = points.length ? 2 : 1; // the dot, and the segment to it
      for (let i = 0; i < remove; i++) scene.remove(pointMeshes.pop());
    },
    resetPoints() {
      points.length = 0;
      while (pointMeshes.length) scene.remove(pointMeshes.pop());
    },
    /** Places the fixture at the crosshair; returns an id for removePlaced, or null. */
    place(fixture) {
      if (!lastPose || !fixture) return null;
      const group = fixtureMesh(fixture);
      group.matrix.fromArray(lastPose);
      scene.add(group);
      const item = { group, anchor: null, pose: lastPose, id: crypto.randomUUID() };
      placed.push(item);
      pendingAnchors.push(item);
      return item.id;
    },
    removePlaced(id) {
      const index = placed.findIndex((item) => item.id === id);
      if (index < 0) return;
      const [item] = placed.splice(index, 1);
      scene.remove(item.group);
      item.anchor?.delete();
    },
    get length() {
      return totalLength();
    },
    end() {
      session.end();
    },
  };
}

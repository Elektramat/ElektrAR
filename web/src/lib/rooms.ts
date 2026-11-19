import { z } from 'zod';

// Rooms ("Mijn ruimtes"), like Project/ProjectStore in the iPhone app: a room is one design.
// In the browser there is no camera measuring, so a cable is the route the user typed in,
// one length per piece along the wall.
const runSchema = z.object({
	id: z.string().min(1),
	cableId: z.string().min(1),
	segments: z.array(z.number().min(0).max(10_000)).min(1)
});

const roomSchema = z.object({
	id: z.string().min(1),
	name: z.string().trim().min(1),
	createdAt: z.string(),
	updatedAt: z.string(),
	runs: z.array(runSchema)
});

export type Run = z.infer<typeof runSchema>;
export type Room = z.infer<typeof roomSchema>;

export const ROOM_SUGGESTIONS = [
	'Woonkamer',
	'Keuken',
	'Slaapkamer',
	'Badkamer',
	'Hal',
	'Zolder',
	'Garage'
];

export const runLength = (run: Pick<Run, 'segments'>) => run.segments.reduce((a, b) => a + b, 0);

export const roomCableLength = (room: Pick<Room, 'runs'>) =>
	room.runs.reduce((sum, run) => sum + runLength(run), 0);

function newId(): string {
	if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return crypto.randomUUID();
	return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

/** null when the name is empty after trimming. */
export function createRoom(name: string, stamp = timestamp()): Room | null {
	const trimmed = name.trim();
	if (!trimmed) return null;
	return { id: newId(), name: trimmed, createdAt: stamp, updatedAt: stamp, runs: [] };
}

/** A finished cable; null when there is nothing to add (no length or an invalid piece). */
export function createRun(cableId: string, segments: number[]): Run | null {
	if (!segments.every((s) => Number.isFinite(s) && s >= 0)) return null;
	const pieces = segments.filter((s) => s > 0);
	if (pieces.length === 0) return null;
	return { id: newId(), cableId, segments: pieces };
}

/** Newest first, like the rooms screen in the app. */
export const sortRooms = (rooms: Room[]) =>
	[...rooms].sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));

/** Reads stored rooms; anything invalid is dropped instead of breaking the app. */
export function parseRooms(raw: string | null): Room[] {
	if (!raw) return [];
	try {
		const result = z.array(z.unknown()).safeParse(JSON.parse(raw));
		if (!result.success) return [];
		return sortRooms(
			result.data.flatMap((entry) => {
				const room = roomSchema.safeParse(entry);
				return room.success ? [room.data] : [];
			})
		);
	} catch {
		return [];
	}
}

/** ISO timestamp for createdAt/updatedAt. */
export const timestamp = (now = new Date()) => now.toISOString();

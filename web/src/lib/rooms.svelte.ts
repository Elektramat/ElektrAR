import { browser } from '$app/env';
import { parseRooms, sortRooms, timestamp, type Room, type Run } from './rooms';

// The saved rooms (see rooms.ts), like ProjectStore in the iPhone app.
const KEY = 'kabelmeter.rooms.v1';

/** Saved rooms in localStorage, saved after every change. */
class Rooms {
	list = $state<Room[]>([]);

	load() {
		if (browser) this.list = parseRooms(localStorage.getItem(KEY));
	}

	get(id: string | null): Room | undefined {
		return id ? this.list.find((r) => r.id === id) : undefined;
	}

	add(room: Room) {
		this.save([room, ...this.list]);
	}

	remove(id: string) {
		this.save(this.list.filter((r) => r.id !== id));
	}

	addRun(roomId: string, run: Run) {
		this.update(roomId, (room) => ({ ...room, runs: [...room.runs, run] }));
	}

	removeRun(roomId: string, runId: string) {
		this.update(roomId, (room) => ({ ...room, runs: room.runs.filter((r) => r.id !== runId) }));
	}

	private update(id: string, change: (room: Room) => Room) {
		const now = timestamp();
		this.save(this.list.map((r) => (r.id === id ? { ...change(r), updatedAt: now } : r)));
	}

	private save(next: Room[]) {
		this.list = sortRooms(next);
		if (browser) localStorage.setItem(KEY, JSON.stringify(this.list));
	}
}

export const rooms = new Rooms();

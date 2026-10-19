package ss2022

const windowBits = 2048

// replayWindow rejects duplicate and too-old packet IDs.
type replayWindow struct {
	highest uint64
	started bool
	seen    [windowBits / 64]uint64
}

// check reports whether id is new and inside the window.
func (w *replayWindow) check(id uint64) bool {
	if !w.started || id > w.highest {
		return true
	}
	if w.highest-id >= windowBits {
		return false
	}
	return !w.has(id)
}

// update records id as seen, sliding the window forward.
func (w *replayWindow) update(id uint64) {
	switch {
	case !w.started:
		w.started, w.highest = true, id
	case id > w.highest && id-w.highest >= windowBits:
		w.seen = [windowBits / 64]uint64{}
		w.highest = id
	case id > w.highest:
		for next := w.highest + 1; next <= id; next++ {
			w.seen[slot(next)] &^= bit(next)
		}
		w.highest = id
	}
	w.seen[slot(id)] |= bit(id)
}

func (w *replayWindow) has(id uint64) bool { return w.seen[slot(id)]&bit(id) != 0 }

func slot(id uint64) uint64 { return (id / 64) % (windowBits / 64) }

func bit(id uint64) uint64 { return 1 << (id % 64) }

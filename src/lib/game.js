/* BERMUDA NXG - Game Engine
 * Preserved from original game.js with full physics and game logic
 */

const K = 1.27
const PR = 52.5
const BR = 25.5
const STEP = 1/240
const RC = 70
const LMAX = 210
const NB = 36
let DEPTH = 112

const HV = 8
const PF1 = 430
const PF2 = 1.0
const PV0 = 520
const EPP = .62
const PCAP = 190

const GS = {
  "white": [840, 307, 0.0491, 0.9522],
  "wood": [840, 306, 0.0474, 0.9519],
  "ice": [840, 305, 0.0535, 0.9429],
  "black": [840, 235, 0.0521, 0.9527],
  "rope": [840, 246, 0.0493, 0.9528],
  "gold": [840, 237, 0.0431, 0.9521],
  "red": [840, 233, 0.0502, 0.9509],
  "blue": [840, 236, 0.0452, 0.9526]
}

export class GameEngine {
  constructor() {
    this.FIELDS = [
      { id: "forest", name: "Forest", W: 1086, H: 1448, L: 195, R: 890, T: 127, B: 1311, cs: 702, g: 130, gs: "wood" },
      { id: "ice", name: "Ice", W: 1086, H: 1448, L: 190, R: 895, T: 134, B: 1308, cs: 700, g: 132, gs: "ice" },
      { id: "ocean", name: "Ocean", W: 1086, H: 1448, L: 191, R: 897, T: 108, B: 1313, cs: 701, g: 132, gs: "blue" },
      { id: "street", name: "Street", W: 1086, H: 1448, L: 182, R: 902, T: 157, B: 1313, cs: 706, g: 134, gs: "gold" },
      { id: "streetarena", name: "Street Arena", W: 1086, H: 1448, L: 194, R: 888, T: 117, B: 1309, cs: 702, g: 130, gs: "rope" },
      { id: "lava", name: "Lava", W: 1086, H: 1448, L: 200, R: 884, T: 127, B: 1305, cs: 699, g: 128, gs: "black" },
      { id: "stadium", name: "Stadium", W: 1086, H: 1448, L: 196, R: 888, T: 115, B: 1311, cs: 701, g: 129, gs: "white" },
      { id: "checker", name: "Checker", W: 1086, H: 1448, L: 193, R: 890, T: 102, B: 1353, cs: 704, g: 130, gs: "red" },
      { id: "futsal", name: "Futsal", W: 1086, H: 1448, L: 190, R: 895, T: 104, B: 1318, cs: 697, g: 132, gs: "gold" },
      { id: "arena", name: "Arena", W: 1086, H: 1448, L: 199, R: 884, T: 118, B: 1313, cs: 694, g: 128, gs: "red" },
      { id: "arena2", name: "Grand Arena", W: 1086, H: 1448, L: 164, R: 921, T: 135, B: 1302, cs: 703, g: 134, gs: "gold" },
      { id: "desert", name: "Desert", W: 1086, H: 1448, L: 163, R: 920, T: 84, B: 1315, cs: 694, g: 134, gs: "black" },
      { id: "grove", name: "Grove", W: 1086, H: 1448, L: 172, R: 918, T: 108, B: 1320, cs: 695, g: 134, gs: "rope" },
      { id: "pool", name: "Pool", W: 1086, H: 1448, L: 160, R: 925, T: 98, B: 1312, cs: 697, g: 134, gs: "white" },
      { id: "neon", name: "Neon Tech", W: 1024, H: 1536, L: 141, R: 883, T: 131, B: 1385, cs: 745, g: 139, gs: "black" },
      { id: "royal", name: "Royal", W: 1024, H: 1536, L: 148, R: 877, T: 147, B: 1350, cs: 730, g: 136, gs: "gold" },
      { id: "mahogany", name: "Mahogany", W: 1024, H: 1536, L: 97, R: 925, T: 90, B: 1393, cs: 729, g: 155, gs: "wood" }
    ]

    this.SET = { lim: 5, snd: 1, vib: 1, mus: 1, fld: 0, ball: 0 }
    this.C = { mode: 'local', names: ['', ''], mirror: false, ai: -1, aiLvl: 1, tt: 0 }
    this.bodies = []
    this.ball = null
    this.score = [0, 0]
    this.phase = 'aim'
    this.turn = 0
    this.drag = null
    this.pause = 0
    this.menuOpen = true
    this.inMatch = false

    this.IMG = {}
    this.SPR = {}
    this.s = 1
    this.ox = 0
    this.oy = 0
    this.Sx = 1
    this.Rx = 0
    this.Ry = 0
  }

  startMatch(cfg) {
    this.C = { ...this.C, ...cfg }
    this.inMatch = true
    this.menuOpen = false
    this.reset(0)
  }

  reset(k) {
    this.bodies = []
    this.phase = 'aim'
    this.drag = null
    this.pause = 0
    this.score = [0, 0]
    this.turn = k

    const f = this.FIELDS[this.SET.fld]
    const F = { l: f.L + 4, r: f.R - 4, t: f.T + 4, b: f.B - 4 }
    const Fw = F.r - F.l
    const Fh = F.b - F.t
    const CX = (F.l + F.r) / 2
    const CY = (F.t + F.b) / 2

    const FORMS = [
      ['1-2-2', 'Balanced', [[.09, 1], [.22, 2], [.36, 2]]],
      ['2-2-1', 'Cautious', [[.10, 2], [.24, 2], [.37, 1]]],
      ['3-1-1', 'Wall', [[.10, 3], [.25, 1], [.37, 1]]],
      ['2-1-2', 'Diamond', [[.10, 2], [.24, 1], [.37, 2]]],
      ['1-3-1', 'Midfield', [[.09, 1], [.23, 3], [.37, 1]]],
      ['1-1-3', 'Attack', [[.09, 1], [.22, 1], [.36, 3]]]
    ]

    const slots = (fi) => {
      const o = []
      for (const [ny, c] of FORMS[fi][2]) {
        for (let i = 0; i < c; i++) {
          o.push([c === 1 ? .5 : c === 2 ? .27 + .46 * i : .17 + .33 * i, ny])
        }
      }
      return o
    }

    // Create pieces for both teams
    for (let cm = 0; cm < 2; cm++) {
      const form = 0
      slots(form).forEach(([nx, ny]) => {
        let x = F.l + PR + 10 + nx * (Fw - 2 * (PR + 10))
        let y = cm ? F.t + ny * Fh : F.b - ny * Fh
        if (this.C.mirror) { x = 2 * CX - x; y = 2 * CY - y }
        const b = this.mk(x, y, cm, PR, 5)
        this.bodies.push(b)
      })
    }

    // Create ball
    this.ball = this.mk(CX, this.C.mirror ? 2 * CY - f.cs : f.cs, 2, BR, 1.5)
    this.bodies.push(this.ball)
  }

  mk(x, y, team, r, m) {
    return { x, y, vx: 0, vy: 0, r, m: 1/m, team, spin: 0, ang: 0 }
  }

  sim(dt) {
    for (const b of this.bodies) {
      b.x += b.vx * dt
      b.y += b.vy * dt

      const sp = Math.hypot(b.vx, b.vy)
      const bl = b === this.ball

      if (sp > 0) {
        if (bl) {
          const f = 610 * K * Math.min(1, sp / (480 * K)) + sp * 0.035
          const ns = sp - f * dt
          if (ns < 12 * K) {
            b.vx = b.vy = 0
          } else {
            const m = Math.max(-34, Math.min(34, b.spin)) * 0.034 * dt
            const cs = Math.cos(m)
            const sn = Math.sin(m)
            const vx = b.vx * cs - b.vy * sn
            const vy = b.vx * sn + b.vy * cs
            const k = Math.min(ns, 2500 * K) / sp
            b.vx = vx * k
            b.vy = vy * k
          }
        } else {
          const ns = sp - (PF1 * K * Math.min(1, sp / (PV0 * K)) + sp * PF2) * dt
          if (ns < 14 * K) {
            b.vx = b.vy = 0
          } else {
            const k = Math.min(ns, 2800 * K) / sp
            b.vx *= k
            b.vy *= k
          }
        }
      }

      if (bl) {
        b.spin *= 1 - (sp > 0 ? 1.05 : 3.2) * dt
        if (Math.abs(b.spin) < 0.02) b.spin = 0
      } else {
        b.spin *= 1 - 2.6 * dt
      }
      b.ang += b.spin * dt

      this.walls(b)
    }

    // Collision detection
    for (let a = 0; a < this.bodies.length; a++) {
      for (let c = a + 1; c < this.bodies.length; c++) {
        this.hit(this.bodies[a], this.bodies[c])
      }
    }
  }

  walls(b) {
    const f = this.FIELDS[this.SET.fld]
    const F = { l: f.L + 4, r: f.R - 4, t: f.T + 4, b: f.B - 4 }
    const bl = b === this.ball
    const eN = (vn) => bl ? 0.84 - 0.22 * Math.min(1, Math.max(0, (vn - 270 * K) / (1350 * K))) : 0.82

    if (b.x - b.r < F.l) {
      b.x = F.l + b.r
      if (b.vx < 0) b.vx *= -eN(-b.vx)
    }
    if (b.x + b.r > F.r) {
      b.x = F.r - b.r
      if (b.vx > 0) b.vx *= -eN(b.vx)
    }
    if (b.y - b.r < F.t) {
      b.y = F.t + b.r
      if (b.vy < 0) b.vy *= -eN(-b.vy)
    }
    if (b.y + b.r > F.b) {
      b.y = F.b - b.r
      if (b.vy > 0) b.vy *= -eN(b.vy)
    }
  }

  hit(a, b) {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let d = Math.hypot(dx, dy)
    const m = a.r + b.r
    if (d >= m) return
    if (d < 1e-4) { dx = 1; dy = 0; d = 1 }

    const nx = dx / d
    const ny = dy / d
    const sm = a.m + b.m

    const pen = Math.max(m - d - 0.3, 0) * 0.9
    a.x -= nx * pen * a.m
    a.y -= ny * pen * a.m
    b.x += nx * pen * b.m
    b.y += ny * pen * b.m

    const vn = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny
    if (vn >= 0) return

    const e = vn < -40 * K ? EPP : 0
    const j = -(1 + e) * vn / sm

    a.vx -= j * nx * a.m
    a.vy -= j * ny * a.m
    b.vx += j * nx * b.m
    b.vy += j * ny * b.m
  }

  setMenuOpen(open) {
    this.menuOpen = open
  }

  get SET() { return this.SET }
  get score() { return this.score }
  get phase() { return this.phase }
}

// Export singleton for use in the app
export const Game = new GameEngine()

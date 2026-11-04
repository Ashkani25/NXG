import { defineStore } from 'pinia'
import { ref, computed } from 'vue'

export const useGameStore = defineStore('game', () => {
  const phase = ref('menu') // menu, playing, paused, ended
  const mode = ref('local') // local, online, bot
  const score = ref([0, 0])
  const turn = ref(0)
  const settings = ref({ snd: 1, mus: 1, vib: 1, fld: 0, ball: 0 })
  const engine = ref(null)

  // Field definitions (preserved from original)
  const FIELDS = [
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

  // Team data
  const TEAMS = []
  const CATS = [
    ["club", "Clubs", ["Inter Milan", "Lazio", "Sevilla", "Tottenham Hotspur", "Wolfsburg", "Persepolis", "Esteghlal", "Al Nassr", "Al Hilal", "Bayer 04 Leverkusen", "RB Leipzig", "Marseille", "Lyon", "Galatasaray", "Fenerbahçe", "Sporting CP", "Shakhtar Donetsk", "Atlético Madrid", "Borussia Dortmund", "Napoli", "Ajax", "Celtic", "Flamengo", "River Plate", "Inter Miami", "Newcastle United", "Aston Villa", "West Ham United", "Everton", "Valencia", "Villarreal", "Fiorentina", "Corinthians", "Real Madrid", "Barcelona", "Bayern Munich", "Juventus", "AC Milan", "Manchester City", "Liverpool", "Arsenal"]],
    ["nat", "National", ["Iran", "Bahrain", "Saudi Arabia", "Morocco", "Turkey", "Mexico", "Argentina", "Uruguay", "Canada", "France", "Brazil", "Germany", "Portugal", "Spain", "England", "Italy", "Netherlands"]],
    ["car", "Cars", ["Mercedes-Benz", "BMW", "Toyota", "Ferrari", "Lamborghini", "Porsche", "Tesla", "Audi", "Ford"]],
    ["lux", "Luxury", ["Louis Vuitton", "Chanel", "Gucci", "Hermes", "Prada", "Dior", "Versace", "Rolex", "Cartier", "Fendi", "Valentino", "Burberry", "Saint Laurent", "Swarovski"]],
    ["spt", "Sports", ["Nike", "Adidas", "Puma", "Under Armour", "New Balance", "Reebok", "Jordan", "Asics", "Wilson", "Speedo", "Converse", "Vans", "NBA", "Umbro"]]
  ]

  for (const [cat, , list] of CATS) {
    list.forEach((name, i) => {
      TEAMS.push({ id: cat + i, cat, name, src: `/assets/teams/${cat}${String(i).padStart(2, '0')}.webp` })
    })
  }

  const currentField = computed(() => FIELDS[settings.value.fld] || FIELDS[0])

  function setEngine(eng) { engine.value = eng }
  function startLocalMatch(opts = {}) {
    mode.value = 'local'
    phase.value = 'playing'
    score.value = [0, 0]
    turn.value = 0
    if (opts.field !== undefined) settings.value.fld = opts.field
    if (opts.ball !== undefined) settings.value.ball = opts.ball
    engine.value?.startMatch?.({ mode: 'local', ...opts })
  }
  function startOnlineMatch(opts = {}) {
    mode.value = 'online'
    phase.value = 'playing'
    score.value = [0, 0]
    turn.value = 0
    engine.value?.startMatch?.({ mode: 'online', ...opts })
  }
  function pause() { if (phase.value === 'playing') phase.value = 'paused' }
  function resume() { if (phase.value === 'paused') phase.value = 'playing' }
  function endMatch() { phase.value = 'ended' }
  function goToMenu() { phase.value = 'menu'; mode.value = 'local'; score.value = [0, 0] }

  return {
    phase, mode, score, turn, settings, engine, FIELDS, TEAMS, CATS, currentField,
    setEngine, startLocalMatch, startOnlineMatch, pause, resume, endMatch, goToMenu
  }
})

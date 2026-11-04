// This file exposes the game engine configuration for Vue
// The actual game.js from www/ will be loaded separately

window.NEXORA_CONFIG = {
  BACKEND: 'supabase', // Use Supabase for online
  APP_NAME: 'BERMUDA NXG',
  API_URL: '', // Your Supabase URL
  WS_URL: '', // Your Supabase URL (for realtime)
  MATCH_SECONDS: 300,
  APP_VERSION: '1.0.0',
  TURN_SECONDS: 15,
  MAX_CHAT_LEN: 140,
  XP_NEED: l => 300 + l * 350,
  LEAGUES: [
    { id: 'bronze', name: 'Bronze', min: 0, color: '#c98a52' },
    { id: 'silver', name: 'Silver', min: 500, color: '#cfd6e2' },
    { id: 'gold', name: 'Gold', min: 1000, color: '#ffd56b' },
    { id: 'platinum', name: 'Platinum', min: 1800, color: '#7fe3ff' },
    { id: 'diamond', name: 'Diamond', min: 2800, color: '#8fa8ff' },
    { id: 'master', name: 'Master', min: 4000, color: '#d58bff' },
    { id: 'legend', name: 'Legend', min: 6000, color: '#ff7a5c' }
  ],
  DAILY_REWARDS: [
    { coins: 100 }, { coins: 150 }, { coins: 200 }, { gems: 5 },
    { coins: 300 }, { coins: 400 }, { coins: 600, gems: 10, chest: 'wood' }
  ],
  CHESTS: {
    wood: { name: 'Wood Chest', img: 'chest_wood', price: 400, cur: 'coins' },
    gold: { name: 'Gold Chest', img: 'chest_gold', price: 60, cur: 'gems' },
    magic: { name: 'Magic Chest', img: 'chest_magic', price: 140, cur: 'gems' }
  },
  QUICK_CHAT: ['Good luck!', 'Nice shot!', 'Wow!', 'Oops...', 'Well played', 'Hurry up!', 'GG', 'Rematch?'],
  EMOJIS: ['😀', '😎', '🔥', '👏', '😮', '😂', '😡', '💪'],
  TOURNAMENTS: []
};

// Game settings exposed to Vue
window.NexoraGame = {
  SET: { lim: 5, snd: 1, vib: 1, mus: 1, fld: 0, ball: 0 },
  TEAMS: [],
  CATS: [
    ["club", "Clubs", ["Inter Milan", "Lazio", "Sevilla", "Tottenham Hotspur", "Wolfsburg", "Persepolis", "Esteghlal", "Al Nassr", "Al Hilal", "Bayer 04 Leverkusen", "RB Leipzig", "Marseille", "Lyon", "Galatasaray", "Fenerbahçe", "Sporting CP", "Shakhtar Donetsk", "Atlético Madrid", "Borussia Dortmund", "Napoli", "Ajax", "Celtic", "Flamengo", "River Plate", "Inter Miami", "Newcastle United", "Aston Villa", "West Ham United", "Everton", "Valencia", "Villarreal", "Fiorentina", "Corinthians", "Real Madrid", "Barcelona", "Bayern Munich", "Juventus", "AC Milan", "Manchester City", "Liverpool", "Arsenal"]],
    ["nat", "National", ["Iran", "Bahrain", "Saudi Arabia", "Morocco", "Turkey", "Mexico", "Argentina", "Uruguay", "Canada", "France", "Brazil", "Germany", "Portugal", "Spain", "England", "Italy", "Netherlands"]],
    ["car", "Cars", ["Mercedes-Benz", "BMW", "Toyota", "Ferrari", "Lamborghini", "Porsche", "Tesla", "Audi", "Ford"]],
    ["lux", "Luxury", ["Louis Vuitton", "Chanel", "Gucci", "Hermes", "Prada", "Dior", "Versace", "Rolex", "Cartier", "Fendi", "Valentino", "Burberry", "Saint Laurent", "Swarovski"]],
    ["spt", "Sports", ["Nike", "Adidas", "Puma", "Under Armour", "New Balance", "Reebok", "Jordan", "Asics", "Wilson", "Speedo", "Converse", "Vans", "NBA", "Umbro"]]
  ],
  FORMS: [
    ['1-2-2', 'Balanced', [[.09, 1], [.22, 2], [.36, 2]]],
    ['2-2-1', 'Cautious', [[.10, 2], [.24, 2], [.37, 1]]],
    ['3-1-1', 'Wall', [[.10, 3], [.25, 1], [.37, 1]]],
    ['2-1-2', 'Diamond', [[.10, 2], [.24, 1], [.37, 2]]],
    ['1-3-1', 'Midfield', [[.09, 1], [.23, 3], [.37, 1]]],
    ['1-1-3', 'Attack', [[.09, 1], [.22, 1], [.36, 3]]]
  ],
  FIELDS: [
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
};

// Build TEAMS array from CATS
for (const [cat, , list] of window.NexoraGame.CATS) {
  list.forEach((name, i) => {
    window.NexoraGame.TEAMS.push({
      id: cat + i,
      cat: cat,
      name: name,
      src: '/assets/teams/' + cat + String(i).padStart(2, '0') + '.webp'
    });
  });
}

// Placeholder functions - real game.js will override these
window.NexoraGame.T = (id) => window.NexoraGame.TEAMS.find(t => t.id === id) || window.NexoraGame.TEAMS[0];
window.NexoraGame.catOf = (id) => {
  const t = window.NexoraGame.T(id);
  return Math.max(0, window.NexoraGame.CATS.findIndex(c => c[0] === t.cat));
};

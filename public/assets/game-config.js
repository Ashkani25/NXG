// NEXORA NXG - Game Configuration
// Updated for Multiplayer (1v1, 2v2, 3v3)

window.NEXORA_CONFIG = {
  // Backend mode: 'colyseus' for online, 'local' for offline
  BACKEND: 'colyseus',
  
  APP_NAME: 'BERMUDA NXG',
  
  // API and WebSocket URLs - UPDATE THIS FOR RAILWAY DEPLOYMENT
  API_URL: 'https://nxg-production.up.railway.app',
  WS_URL: 'wss://nxg-production.up.railway.app',
  
  // Match settings
  MATCH_SECONDS: 300,
  TURN_SECONDS: 15,
  MAX_CHAT_LEN: 140,
  
  // XP calculation per level
  XP_NEED: l => 300 + l * 350,
  
  // Leagues with trophy thresholds
  LEAGUES: [
    { id: 'bronze', name: 'Bronze', min: 0, color: '#c98a52' },
    { id: 'silver', name: 'Silver', min: 500, color: '#cfd6e2' },
    { id: 'gold', name: 'Gold', min: 1000, color: '#ffd56b' },
    { id: 'platinum', name: 'Platinum', min: 1800, color: '#7fe3ff' },
    { id: 'diamond', name: 'Diamond', min: 2800, color: '#8fa8ff' },
    { id: 'master', name: 'Master', min: 4000, color: '#d58bff' },
    { id: 'legend', name: 'Legend', min: 6000, color: '#ff7a5c' }
  ],
  
  // Daily reward cycle
  DAILY_REWARDS: [
    { coins: 100 }, { coins: 150 }, { coins: 200 }, { gems: 5 },
    { coins: 300 }, { coins: 400 }, { coins: 600, gems: 10, chest: 'wood' }
  ],
  
  // Chest shop items
  CHESTS: {
    wood: { name: 'Wood Chest', img: 'chest_wood', price: 400, cur: 'coins' },
    gold: { name: 'Gold Chest', img: 'chest_gold', price: 60, cur: 'gems' },
    magic: { name: 'Magic Chest', img: 'chest_magic', price: 140, cur: 'gems' }
  },
  
  // Quick chat messages
  QUICK_CHAT: ['Good luck!', 'Nice shot!', 'Wow!', 'Oops...', 'Well played', 'Hurry up!', 'GG', 'Rematch?'],
  
  // Emojis
  EMOJIS: ['😀', '😎', '🔥', '👏', '😮', '😂', '😡', '💪'],
  
  // Game modes
  GAME_MODES: [
    { id: '1v1', name: '1 vs 1', players: 2, teamSize: 1 },
    { id: '2v2', name: '2 vs 2', players: 4, teamSize: 2 },
    { id: '3v3', name: '3 vs 3', players: 6, teamSize: 3 }
  ],
  
  // Match time options (in seconds)
  MATCH_TIMES: [
    { value: 180, label: '3 min' },
    { value: 300, label: '5 min' },
    { value: 420, label: '7 min' },
    { value: 600, label: '10 min' }
  ],
  
  APP_VERSION: '2.0.0'
};

// Game engine configuration
window.NexoraGame = {
  SET: { lim: 5, snd: 1, vib: 1, mus: 1, fld: 0, ball: 0 },
  
  // Team categories
  CATS: [
    ["club", "Clubs", ["Real Madrid", "Barcelona", "Manchester City", "Manchester United", "Liverpool", "Arsenal", "Chelsea", "Bayern Munich", "Borussia Dortmund", "Paris Saint-Germain", "Inter Milan", "AC Milan", "Juventus", "Atletico Madrid", "Ajax", "Benfica", "Porto", "Boca Juniors", "River Plate", "Flamengo", "Al Nassr", "Al Hilal", "Roma", "Besiktas", "Tottenham", "Marseille", "Napoli", "Sporting CP", "Sevilla", "Valencia", "PSV", "Celtic", "Bayer Leverkusen", "RB Leipzig", "Lyon", "Galatasaray", "Fenerbahce", "Shakhtar Donetsk", "Inter Miami", "Newcastle United", "Aston Villa", "West Ham United", "Everton", "Villarreal", "Fiorentina", "Corinthians", "Lazio", "Wolfsburg", "Persepolis", "Esteghlal"]],
    ["nat", "National", ["Argentina", "Brazil", "France", "Germany", "Portugal", "Spain", "Italy", "England", "Netherlands", "Belgium", "Uruguay", "Sweden", "Poland", "Denmark", "Croatia", "Switzerland", "Mexico", "USA", "Japan", "South Korea", "Australia", "Senegal", "Morocco", "Tunisia", "Egypt", "Iceland", "Iran", "Qatar", "Saudi Arabia", "Colombia", "Canada", "Turkey"]],
    ["vip", "VIP", ["Nova Blue", "Aurum Crest", "Emerald Core", "Specter Wings", "Infernal Edge", "Timber Blaze", "Chrome Vortex", "Crimson Pulse", "Thunder Gold", "Jade Marble", "Kakero Noir", "Kakero Frost"]],
    ["car", "Cars", ["Lamborghini", "Ferrari", "Rolls-Royce", "Mercedes-Benz", "BMW", "Porsche", "Maserati", "Aston Martin", "Bentley", "Bugatti", "Lexus", "Cadillac", "McLaren", "Tesla"]],
    ["lux", "Luxury", ["Louis Vuitton", "Chanel", "Gucci", "Hermes", "Prada", "Dior", "Versace", "Rolex", "Cartier", "Fendi", "Valentino", "Burberry", "Saint Laurent", "Swarovski"]],
    ["spt", "Sports", ["Nike", "Adidas", "Puma", "Under Armour", "New Balance", "Reebok", "Jordan", "Asics", "Wilson", "Speedo", "Converse", "Vans", "NBA", "Umbro"]]
  ],
  
  // Field definitions
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
  ],
  
  // Team formations
  FORMS: [
    ['1-2-2', 'Balanced', [[.09, 1], [.22, 2], [.36, 2]]],
    ['2-2-1', 'Cautious', [[.10, 2], [.24, 2], [.37, 1]]],
    ['3-1-1', 'Wall', [[.10, 3], [.25, 1], [.37, 1]]],
    ['2-1-2', 'Diamond', [[.10, 2], [.24, 1], [.37, 2]]],
    ['1-3-1', 'Midfield', [[.09, 1], [.23, 3], [.37, 1]]],
    ['1-1-3', 'Attack', [[.09, 1], [.22, 1], [.36, 3]]]
  ],
  
  // Number of balls
  NB: 36
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

// Helper functions
window.NexoraGame.T = id => window.NexoraGame.TEAMS.find(t => t.id === id) || window.NexoraGame.TEAMS[0];
window.NexoraGame.catOf = id => Math.max(0, window.NexoraGame.CATS.findIndex(c => c[0] === window.NexoraGame.T(id).cat));
window.NexoraGame.field = id => window.NexoraGame.FIELDS.find(f => f.id === id) || window.NexoraGame.FIELDS[0];

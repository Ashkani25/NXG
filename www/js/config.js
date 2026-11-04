/* NEXORA – central config. Everything the UI + backend adapters share lives here.
   Backend: colyseus (online) or local (offline practice). */
window.NEXORA_CONFIG = {
  BACKEND: 'colyseus',              // 'colyseus' = real online server (server/) | 'local' = offline practice only
  APP_NAME: 'BERMUDA NXG',
  API_URL: '',                      // e.g. https://api.yourdomain.com   (Express REST, served by server/)
  WS_URL: '',                       // e.g. wss://api.yourdomain.com     (Colyseus; empty = derived from API_URL)
  MATCH_SECONDS: 300,               // every match = 5 minutes, unlimited goals, golden goal if tied
  APP_VERSION: '1.1.0',
  TURN_SECONDS: 15,                 // online turn timer
    MAX_CHAT_LEN: 140,
  XP_NEED: l => 300 + l * 350,      // xp needed to go from level l to l+1  (level 12 -> 4500)
  LEAGUES: [                        // trophies thresholds (3 divisions each: III, II, I)
    { id: 'bronze',   name: 'Bronze',   min: 0,    color: '#c98a52' },
    { id: 'silver',   name: 'Silver',   min: 500,  color: '#cfd6e2' },
    { id: 'gold',     name: 'Gold',     min: 1000, color: '#ffd56b' },
    { id: 'platinum', name: 'Platinum', min: 1800, color: '#7fe3ff' },
    { id: 'diamond',  name: 'Diamond',  min: 2800, color: '#8fa8ff' },
    { id: 'master',   name: 'Master',   min: 4000, color: '#d58bff' },
    { id: 'legend',   name: 'Legend',   min: 6000, color: '#ff7a5c' }
  ],
  DAILY_REWARDS: [                  // 7-day streak
    { coins: 100 }, { coins: 150 }, { coins: 200 }, { gems: 5 }, { coins: 300 }, { coins: 400 }, { coins: 600, gems: 10, chest: 'wood' }
  ],
  CHESTS: {
    wood:  { name: 'Wood Chest',  img: 'chest_wood',  price: 400,  cur: 'coins' },
    gold:  { name: 'Gold Chest',  img: 'chest_gold',  price: 60,   cur: 'gems'  },
    magic: { name: 'Magic Chest', img: 'chest_magic', price: 140,  cur: 'gems'  }
  },
  COIN_PACKS: [                     // real-money products: wire to Google Play Billing + server verification
    { id: 'coins_s', name: '2,000 Coins',  coins: 2000,  price: '$0.99', img: 'i_coin' },
    { id: 'coins_m', name: '6,500 Coins',  coins: 6500,  price: '$2.99', img: 'i_coin' },
    { id: 'coins_l', name: '15,000 Coins', coins: 15000, price: '$5.99', img: 'i_coin' },
    { id: 'gems_s',  name: '80 Gems',      gems: 80,      price: '$1.99', img: 'i_gem' },
    { id: 'gems_m',  name: '250 Gems',     gems: 250,     price: '$4.99', img: 'i_gem' }
  ],
  QUICK_CHAT: ['Good luck!', 'Nice shot!', 'Wow!', 'Oops...', 'Well played', 'Hurry up!', 'GG', 'Rematch?'],
  EMOJIS: ['😀', '😎', '🔥', '👏', '😮', '😂', '😡', '💪'],
  TOURNAMENTS: []                   // tournaments come from the server table `tournaments`; nothing is hard-coded
};
/* shared price tables (UI shows them, server/src/lib.js enforces the same numbers) */
window.NexoraPrices = (() => { const FB = [0, 4, 5], FF = ['stadium', 'forest', 'ice', 'street'];
  return { freeBalls: FB, freeFields: FF, ball: i => FB.includes(i) ? 0 : i >= 13 ? 800 + (i - 13) * 100 : 300 + (i % 5) * 300, field: id => FF.includes(id) ? 0 : 500 + (id.length % 4) * 400 } })();

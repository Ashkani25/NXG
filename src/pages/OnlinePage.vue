<template>
  <div class="scr online">
    <div class="bgmagic"></div>
    
    <!-- Header -->
    <div class="top">
      <button class="ibtn bk" @click="$router.back()">
        <img src="/assets/nx3/a_left.webp" alt="">
      </button>
      <h2 class="gold">ONLINE</h2>
      <div class="sp"></div>
    </div>
    
    <div class="page">
      <!-- Connection Status -->
      <div class="connection-status" :class="{ connected: isConnected }">
        <span class="dot"></span>
        {{ isConnected ? 'Connected' : 'Offline' }}
      </div>
      
      <!-- Username Entry (if not logged in) -->
      <div v-if="!player.isOnline && !player.isGuest" class="card pad auth-section">
        <h3>Enter Your Name</h3>
        <p class="mut">This name will be visible to other players</p>
        <input 
          class="inp" 
          v-model="username" 
          placeholder="Your name..." 
          maxlength="16"
          @keyup.enter="enterOnline"
        >
        <button class="btn gold block" @click="enterOnline">
          ENTER ONLINE
        </button>
        <button class="btn ghost block" @click="playAsGuest">
          PLAY AS GUEST
        </button>
      </div>
      
      <!-- Online Menu (if logged in) -->
      <div v-else class="online-menu">
        <!-- Welcome -->
        <div class="welcome">
          <div class="av lg">
            <img :src="teamAvatar" alt="">
          </div>
          <h3>{{ player.profile.name }}</h3>
          <div class="chip">
            <span class="dot online-dot"></span>
            ONLINE
          </div>
        </div>
        
        <!-- Quick Match Section -->
        <div class="section">
          <h4>QUICK MATCH</h4>
          <div class="mode-grid">
            <div 
              v-for="mode in gameModes" 
              :key="mode.id"
              class="mode-card"
              :class="{ selected: selectedMode === mode.id }"
              @click="selectedMode = mode.id"
            >
              <b>{{ mode.name }}</b>
              <small>{{ mode.players }} players</small>
            </div>
          </div>
          <button 
            class="btn gold block cta" 
            @click="quickMatch"
            :disabled="status === 'searching' || !selectedMode"
          >
            <span v-if="status === 'searching'">SEARCHING...</span>
            <span v-else>FIND MATCH</span>
          </button>
          <button 
            v-if="status === 'searching'" 
            class="btn dark block"
            @click="cancelSearch"
          >
            CANCEL
          </button>
        </div>
        
        <!-- Room Actions -->
        <div class="section">
          <h4>ROOMS</h4>
          <div class="action-grid">
            <div class="oc" @click="showCreateRoom = true">
              <img src="/assets/nx3/k_team.webp" alt="">
              <b>CREATE ROOM</b>
              <small>Start a new private room</small>
            </div>
            
            <div class="oc" @click="showJoinRoom = true">
              <img src="/assets/nx3/c_play.webp" alt="">
              <b>JOIN ROOM</b>
              <small>Enter 6-digit code</small>
            </div>
            
            <div class="oc" @click="showRoomBrowser = true">
              <img src="/assets/nx3/c_rankings.webp" alt="">
              <b>BROWSE ROOMS</b>
              <small>Find public games</small>
            </div>
          </div>
        </div>
        
        <!-- Sign Out -->
        <button class="btn ghost block" @click="signOut">
          Sign Out
        </button>
      </div>
    </div>
    
    <!-- Create Room Modal -->
    <div v-if="showCreateRoom" class="modal-overlay" @click.self="showCreateRoom = false">
      <div class="modal card pad">
        <h3>CREATE ROOM</h3>
        
        <div class="form-group">
          <label>Room Name (optional)</label>
          <input class="inp" v-model="createOptions.name" placeholder="My Room">
        </div>
        
        <div class="form-group">
          <label>Players</label>
          <div class="mode-select">
            <button 
              v-for="m in gameModes" 
              :key="m.id"
              :class="{ active: createOptions.capacity === m.players }"
              @click="createOptions.capacity = m.players"
            >
              {{ m.name }}
            </button>
          </div>
        </div>
        
        <div class="form-group">
          <label>Field</label>
          <select class="inp" v-model="createOptions.field">
            <option v-for="f in game.FIELDS" :key="f.id" :value="f.id">{{ f.name }}</option>
          </select>
        </div>
        
        <div class="form-group">
          <label>Match Time: {{ matchTimeLabel }}</label>
          <input type="range" min="180" max="600" step="60" v-model.number="createOptions.matchTime">
        </div>
        
        <div class="form-group">
          <label>
            <input type="checkbox" v-model="createOptions.public">
            Public Room (visible to others)
          </label>
        </div>
        
        <div class="acts">
          <button class="btn dark" @click="showCreateRoom = false">Cancel</button>
          <button class="btn gold" @click="createRoom" :disabled="creating">
            {{ creating ? 'CREATING...' : 'CREATE' }}
          </button>
        </div>
      </div>
    </div>
    
    <!-- Join Room Modal -->
    <div v-if="showJoinRoom" class="modal-overlay" @click.self="showJoinRoom = false">
      <div class="modal card pad">
        <h3>JOIN ROOM</h3>
        <input 
          class="inp code-input" 
          v-model="joinCode" 
          placeholder="Enter 6-digit code"
          maxlength="6"
          @keyup.enter="joinRoom"
        >
        <div class="acts">
          <button class="btn dark" @click="showJoinRoom = false">Cancel</button>
          <button class="btn gold" @click="joinRoom" :disabled="joining">
            {{ joining ? 'JOINING...' : 'JOIN' }}
          </button>
        </div>
      </div>
    </div>
    
    <!-- Room Browser Modal -->
    <div v-if="showRoomBrowser" class="modal-overlay" @click.self="showRoomBrowser = false">
      <div class="modal card pad wide">
        <h3>PUBLIC ROOMS</h3>
        <div class="room-list" v-if="publicRooms.length">
          <div 
            v-for="room in publicRooms" 
            :key="room.code"
            class="room-item"
            @click="joinBrowserRoom(room.code)"
          >
            <div class="ri-info">
              <b>{{ room.name }}</b>
              <small>by {{ room.host?.name || 'Unknown' }}</small>
            </div>
            <div class="ri-meta">
              <span class="chip">{{ room.mode || '1v1' }}</span>
              <span>{{ room.players }}/{{ room.capacity }}</span>
            </div>
          </div>
        </div>
        <div v-else class="empty">
          <p>No public rooms available</p>
          <small>Create one to start playing!</small>
        </div>
        <div class="acts">
          <button class="btn dark" @click="showRoomBrowser = false">Close</button>
          <button class="btn" @click="refreshRooms">Refresh</button>
        </div>
      </div>
    </div>
    
    <!-- Bottom Nav -->
    <div class="navbar">
      <button @click="$router.push('/')">
        <img src="/assets/nx3/t_home.webp" alt=""><span>HOME</span>
      </button>
      <button @click="$router.push('/team-select')">
        <img src="/assets/nx3/t_user.webp" alt=""><span>TEAM</span>
      </button>
      <button class="mid" @click="$router.push('/play')">
        <b>PLAY</b>
      </button>
      <button class="on" @click="$router.push('/online')">
        <img src="/assets/nx3/t_trophy.webp" alt=""><span>ONLINE</span>
      </button>
      <button @click="$router.push('/settings')">
        <img src="/assets/nx3/gear.webp" alt=""><span>SETTINGS</span>
      </button>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { usePlayerStore } from '@/stores/player'
import { useMatchmakingStore } from '@/stores/matchmaking'
import { useGameStore } from '@/stores/game'

const router = useRouter()
const player = usePlayerStore()
const match = useMatchmakingStore()
const game = useGameStore()

const username = ref('')
const isConnected = ref(false)

// Modals
const showCreateRoom = ref(false)
const showJoinRoom = ref(false)
const showRoomBrowser = ref(false)

// Create room options
const createOptions = ref({
  name: '',
  capacity: 2,
  field: 'stadium',
  matchTime: 300,
  public: false
})

const joinCode = ref('')
const creating = ref(false)
const joining = ref(false)
const selectedMode = ref('1v1')

// Public rooms list
const publicRooms = ref([])

// Game modes
const gameModes = [
  { id: '1v1', name: '1 vs 1', players: 2, teamSize: 1 },
  { id: '2v2', name: '2 vs 2', players: 4, teamSize: 2 },
  { id: '3v3', name: '3 vs 3', players: 6, teamSize: 3 }
]

const matchTimeLabel = computed(() => {
  const mins = createOptions.value.matchTime / 60
  return `${mins} min`
})

const teamAvatar = computed(() => {
  const team = game.TEAMS.find(t => t.id === player.profile.team)
  return team?.src || '/assets/teams/club0.webp'
})

const status = computed(() => match.status)

async function enterOnline() {
  if (!username.value.trim()) return
  await player.signInOnline(username.value.trim())
}

async function playAsGuest() {
  await player.signInGuest()
}

function signOut() {
  player.isOnline = false
  player.isGuest = true
}

async function quickMatch() {
  if (!selectedMode.value) return
  try {
    await match.joinQueue(selectedMode.value)
    // In a real implementation, this would connect to Colyseus queue
    // and wait for a match to be found
  } catch (e) {
    alert('Failed to join queue: ' + e.message)
  }
}

async function cancelSearch() {
  await match.cancelQueue()
}

async function createRoom() {
  creating.value = true
  try {
    const code = await match.createRoom({
      name: createOptions.value.name,
      capacity: createOptions.value.capacity,
      field: createOptions.value.field,
      matchTime: createOptions.value.matchTime,
      public: createOptions.value.public
    })
    showCreateRoom.value = false
    router.push('/room/' + code)
  } catch (e) {
    alert('Failed to create room: ' + e.message)
  } finally {
    creating.value = false
  }
}

async function joinRoom() {
  if (!joinCode.value.trim()) return
  joining.value = true
  try {
    await match.joinRoom(joinCode.value.trim())
    showJoinRoom.value = false
    router.push('/room/' + joinCode.value.trim().toUpperCase())
  } catch (e) {
    alert('Failed to join: ' + e.message)
  } finally {
    joining.value = false
  }
}

async function joinBrowserRoom(code) {
  showRoomBrowser.value = false
  try {
    await match.joinRoom(code)
    router.push('/room/' + code)
  } catch (e) {
    alert('Failed to join: ' + e.message)
  }
}

async function refreshRooms() {
  try {
    const res = await fetch('/rooms')
    if (res.ok) {
      publicRooms.value = await res.json()
    }
  } catch (e) {
    console.error('Failed to fetch rooms:', e)
  }
}

onMounted(() => {
  // Check connection status
  if (window.NEXORA_CONFIG?.API_URL) {
    fetch(window.NEXORA_CONFIG.API_URL + '/health')
      .then(r => r.ok)
      .then(ok => isConnected.value = ok)
      .catch(() => isConnected.value = false)
  }
  
  // Refresh public rooms
  refreshRooms()
})
</script>

<style scoped>
.online {
  min-height: 100vh;
  background: #03060d;
}

.connection-status {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 16px;
  background: rgba(255,50,50,0.2);
  border-radius: 20px;
  font-size: 12px;
  margin-bottom: 16px;
}

.connection-status.connected {
  background: rgba(50,255,100,0.2);
}

.connection-status .dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #f55;
}

.connection-status.connected .dot {
  background: #5f5;
}

.auth-section {
  margin-top: 20px;
}

.auth-section h3 {
  color: #ffd56b;
  margin-bottom: 8px;
}

.auth-section .mut {
  color: #888;
  font-size: 12px;
  margin-bottom: 16px;
}

.welcome {
  text-align: center;
  padding: 20px;
}

.welcome .av {
  width: 80px;
  height: 80px;
  margin: 0 auto 12px;
  border-radius: 50%;
  overflow: hidden;
  border: 3px solid #ffd56b;
}

.welcome .av img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.welcome h3 {
  color: #fff;
  margin-bottom: 8px;
}

.section {
  margin: 24px 0;
}

.section h4 {
  color: #ffd56b;
  font-size: 12px;
  margin-bottom: 12px;
}

.mode-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 8px;
  margin-bottom: 12px;
}

.mode-card {
  background: rgba(255,255,255,0.05);
  border: 2px solid transparent;
  border-radius: 12px;
  padding: 12px;
  text-align: center;
  cursor: pointer;
  transition: all 0.2s;
}

.mode-card.selected {
  border-color: #ffd56b;
  background: rgba(255,213,107,0.1);
}

.mode-card b {
  display: block;
  color: #fff;
  font-size: 14px;
}

.mode-card small {
  color: #888;
  font-size: 10px;
}

.action-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 12px;
}

.oc {
  background: rgba(255,255,255,0.05);
  border-radius: 12px;
  padding: 16px 8px;
  text-align: center;
  cursor: pointer;
  transition: all 0.2s;
}

.oc:hover {
  background: rgba(255,255,255,0.1);
}

.oc img {
  width: 40px;
  height: 40px;
  margin-bottom: 8px;
}

.oc b {
  display: block;
  color: #ffd56b;
  font-size: 11px;
  margin-bottom: 4px;
}

.oc small {
  color: #888;
  font-size: 9px;
}

.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0,0,0,0.8);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  padding: 20px;
}

.modal {
  width: 100%;
  max-width: 360px;
}

.modal.wide {
  max-width: 500px;
}

.modal h3 {
  color: #ffd56b;
  margin-bottom: 20px;
  text-align: center;
}

.form-group {
  margin-bottom: 16px;
}

.form-group label {
  display: block;
  color: #888;
  font-size: 12px;
  margin-bottom: 6px;
}

.form-group .inp {
  width: 100%;
}

.mode-select {
  display: flex;
  gap: 8px;
}

.mode-select button {
  flex: 1;
  padding: 8px;
  background: rgba(255,255,255,0.05);
  border: 2px solid transparent;
  border-radius: 8px;
  color: #888;
  font-size: 12px;
  cursor: pointer;
}

.mode-select button.active {
  border-color: #ffd56b;
  color: #ffd56b;
  background: rgba(255,213,107,0.1);
}

.code-input {
  text-align: center;
  font-size: 24px;
  letter-spacing: 8px;
  text-transform: uppercase;
}

.acts {
  display: flex;
  gap: 12px;
  margin-top: 20px;
}

.acts .btn {
  flex: 1;
}

.room-list {
  max-height: 300px;
  overflow-y: auto;
}

.room-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 12px;
  background: rgba(255,255,255,0.03);
  border-radius: 8px;
  margin-bottom: 8px;
  cursor: pointer;
}

.room-item:hover {
  background: rgba(255,255,255,0.08);
}

.ri-info b {
  display: block;
  color: #fff;
  font-size: 14px;
}

.ri-info small {
  color: #888;
  font-size: 11px;
}

.ri-meta {
  text-align: right;
}

.ri-meta .chip {
  display: inline-block;
  background: rgba(255,213,107,0.2);
  color: #ffd56b;
  padding: 2px 8px;
  border-radius: 10px;
  font-size: 10px;
  margin-bottom: 4px;
}

.ri-meta span:last-child {
  display: block;
  color: #888;
  font-size: 12px;
}

.empty {
  text-align: center;
  padding: 40px;
  color: #888;
}

.empty p {
  margin-bottom: 8px;
}
</style>

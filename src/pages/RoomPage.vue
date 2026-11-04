<template>
  <div class="scr room">
    <div class="bgmagic"></div>
    
    <!-- Header -->
    <div class="top">
      <button class="ibtn bk" @click="leave">
        <img src="/assets/nx3/a_left.webp" alt="">
      </button>
      <h2 class="gold">ROOM</h2>
      <button class="ibtn" @click="showSettings = true">
        <img src="/assets/nx3/gear.webp" alt="">
      </button>
    </div>
    
    <div class="page">
      <!-- Room Code -->
      <div class="room-code">
        <small>ROOM CODE</small>
        <b class="code">{{ match.roomCode }}</b>
        <button class="btn ghost sm" @click="copyCode">
          <img src="/assets/nx3/gear.webp" alt="" style="width:14px">
          COPY
        </button>
      </div>
      
      <!-- Room Info -->
      <div class="room-info">
        <div class="ri-item">
          <span class="label">Mode</span>
          <span class="value">{{ modeLabel }}</span>
        </div>
        <div class="ri-item">
          <span class="label">Field</span>
          <span class="value">{{ match.roomSettings?.field || 'Stadium' }}</span>
        </div>
        <div class="ri-item">
          <span class="label">Time</span>
          <span class="value">{{ matchTimeLabel }}</span>
        </div>
      </div>
      
      <!-- Teams Display -->
      <div class="teams-display">
        <!-- Team 0 -->
        <div class="team-column">
          <div class="team-header">
            <img src="/assets/nx3/t_trophy.webp" alt="" class="team-icon">
            <span>TEAM 1</span>
          </div>
          <div class="player-slots">
            <div 
              v-for="(player, idx) in team0Players" 
              :key="player?.id || 'empty-' + idx"
              class="player-slot"
              :class="{ filled: !!player, empty: !player }"
            >
              <template v-if="player">
                <div class="av">
                  <img :src="getTeamAvatar(player.team)" alt="">
                </div>
                <div class="pi">
                  <b>{{ player.name }}</b>
                  <span v-if="player.isHost" class="badge host">HOST</span>
                  <span v-if="player.ready" class="badge ready">READY</span>
                </div>
                <div class="status" v-if="player.ready">
                  <img src="/assets/nx3/i_star.webp" alt="">
                </div>
              </template>
              <template v-else>
                <div class="av empty-slot">?</div>
                <div class="pi">
                  <b class="mut">Waiting...</b>
                </div>
              </template>
            </div>
          </div>
        </div>
        
        <!-- VS Divider -->
        <div class="vs-divider">VS</div>
        
        <!-- Team 1 -->
        <div class="team-column">
          <div class="team-header">
            <img src="/assets/nx3/t_trophy.webp" alt="" class="team-icon">
            <span>TEAM 2</span>
          </div>
          <div class="player-slots">
            <div 
              v-for="(player, idx) in team1Players" 
              :key="player?.id || 'empty-' + idx"
              class="player-slot"
              :class="{ filled: !!player, empty: !player }"
            >
              <template v-if="player">
                <div class="av">
                  <img :src="getTeamAvatar(player.team)" alt="">
                </div>
                <div class="pi">
                  <b>{{ player.name }}</b>
                  <span v-if="player.isHost" class="badge host">HOST</span>
                  <span v-if="player.ready" class="badge ready">READY</span>
                </div>
                <div class="status" v-if="player.ready">
                  <img src="/assets/nx3/i_star.webp" alt="">
                </div>
              </template>
              <template v-else>
                <div class="av empty-slot">?</div>
                <div class="pi">
                  <b class="mut">Waiting...</b>
                </div>
              </template>
            </div>
          </div>
        </div>
      </div>
      
      <!-- Spectators Count -->
      <div v-if="match.spectators > 0" class="spectators-count">
        <img src="/assets/nx3/c_friends.webp" alt="">
        <span>{{ match.spectators }} watching</span>
      </div>
      
      <!-- Status Messages -->
      <div class="status-area">
        <div v-if="status === 'waiting'" class="s waiting">
          Waiting for players...
        </div>
        <div v-else-if="status === 'ready'" class="s ready">
          All players ready! Starting soon...
        </div>
        <div v-else-if="status === 'starting'" class="s starting">
          <div class="spinner"></div>
          Starting match...
        </div>
        <div v-else-if="status === 'searching'" class="s searching">
          <div class="spinner"></div>
          Finding match...
        </div>
      </div>
      
      <!-- Action Buttons -->
      <div class="actions">
        <!-- Ready/Unready (non-host) -->
        <button 
          v-if="!match.isHost && status !== 'starting'"
          class="btn block"
          :class="isReady ? 'dark' : 'gold'"
          @click="toggleReady"
        >
          {{ isReady ? 'NOT READY' : 'READY' }}
        </button>
        
        <!-- Start Match (host only) -->
        <button 
          v-if="match.isHost && allReady && status !== 'starting'"
          class="btn gold block cta"
          @click="startMatch"
        >
          START MATCH
        </button>
        
        <!-- Leave Room -->
        <button class="btn dark block" @click="leave">
          {{ match.isHost ? 'DELETE ROOM' : 'LEAVE' }}
        </button>
      </div>
    </div>
    
    <!-- Room Settings Modal (Host only) -->
    <div v-if="showSettings && match.isHost" class="modal-overlay" @click.self="showSettings = false">
      <div class="modal card pad">
        <h3>ROOM SETTINGS</h3>
        
        <div class="form-group">
          <label>Field</label>
          <select class="inp" v-model="roomSettings.field">
            <option v-for="f in game.FIELDS" :key="f.id" :value="f.id">{{ f.name }}</option>
          </select>
        </div>
        
        <div class="form-group">
          <label>Match Time: {{ settingsMatchTimeLabel }}</label>
          <input type="range" min="180" max="600" step="60" v-model.number="roomSettings.matchTime">
        </div>
        
        <div class="form-group">
          <label>
            <input type="checkbox" v-model="roomSettings.public">
            Public Room
          </label>
        </div>
        
        <div class="acts">
          <button class="btn dark" @click="showSettings = false">Cancel</button>
          <button class="btn gold" @click="saveSettings">Save</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { usePlayerStore } from '@/stores/player'
import { useMatchmakingStore } from '@/stores/matchmaking'
import { useGameStore } from '@/stores/game'

const route = useRoute()
const router = useRouter()
const player = usePlayerStore()
const match = useMatchmakingStore()
const game = useGameStore()

const showSettings = ref(false)

const roomSettings = ref({
  field: 'stadium',
  matchTime: 300,
  public: false
})

const status = computed(() => match.status)

// Player's own ready state
const isReady = computed(() => {
  const myPlayer = match.players.find(p => p.id === player.profile.id)
  return myPlayer?.ready || false
})

// Check if all players are ready
const allReady = computed(() => {
  if (match.players.length < match.capacity) return false
  return match.players.every(p => p.ready)
})

// Mode label
const modeLabel = computed(() => {
  const players = match.capacity || 2
  if (players === 2) return '1 vs 1'
  if (players === 4) return '2 vs 2'
  return '3 vs 3'
})

// Match time label
const matchTimeLabel = computed(() => {
  const seconds = match.roomSettings?.matchTime || 300
  const mins = seconds / 60
  return `${mins} min`
})

const settingsMatchTimeLabel = computed(() => {
  const mins = roomSettings.value.matchTime / 60
  return `${mins} min`
})

// Team players
const team0Players = computed(() => {
  const teamSize = match.teamSize || 1
  const players = []
  for (let i = 0; i < teamSize; i++) {
    players.push(match.players.find(p => p.team === 0 && p.slot === i) || null)
  }
  return players
})

const team1Players = computed(() => {
  const teamSize = match.teamSize || 1
  const players = []
  for (let i = 0; i < teamSize; i++) {
    players.push(match.players.find(p => p.team === 1 && p.slot === i) || null)
  }
  return players
})

function getTeamAvatar(teamId) {
  // Get team avatar based on player's selected team
  const team = game.TEAMS[teamId * 10] // Simplified - use first team of each category
  return team?.src || '/assets/teams/club0.webp'
}

function copyCode() {
  navigator.clipboard.writeText(match.roomCode)
  alert('Room code copied!')
}

async function toggleReady() {
  await match.setReady(!isReady.value)
}

async function startMatch() {
  try {
    await match.startMatch()
    // Match will start and redirect to play page
  } catch (e) {
    alert('Failed to start: ' + e.message)
  }
}

async function leave() {
  await match.leaveRoom()
  router.push('/online')
}

async function saveSettings() {
  // Update room settings through backend
  showSettings.value = false
}

onMounted(() => {
  // Join room if not already in
  const code = route.params.code?.toUpperCase()
  if (code && !match.isInRoom) {
    match.joinRoom(code).catch(e => {
      alert('Failed to join room: ' + e.message)
      router.push('/online')
    })
  }
  
  // Initialize room settings from match
  if (match.roomSettings) {
    roomSettings.value = { ...match.roomSettings }
  }
})

onUnmounted(() => {
  // Don't leave room when navigating away - let it persist
})
</script>

<style scoped>
.room {
  min-height: 100vh;
  background: #03060d;
}

.room-code {
  text-align: center;
  padding: 20px;
  background: rgba(255,255,255,0.03);
  border-radius: 16px;
  margin-bottom: 16px;
}

.room-code small {
  color: #888;
  font-size: 11px;
  display: block;
  margin-bottom: 4px;
}

.room-code .code {
  display: block;
  font-size: 32px;
  letter-spacing: 6px;
  color: #ffd56b;
  margin-bottom: 12px;
}

.room-info {
  display: flex;
  justify-content: center;
  gap: 20px;
  margin-bottom: 20px;
}

.ri-item {
  text-align: center;
}

.ri-item .label {
  display: block;
  color: #888;
  font-size: 10px;
  margin-bottom: 2px;
}

.ri-item .value {
  color: #fff;
  font-size: 13px;
}

.teams-display {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 16px;
  margin-bottom: 20px;
}

.team-column {
  flex: 1;
}

.team-header {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 12px;
  padding: 8px;
  background: rgba(255,255,255,0.03);
  border-radius: 8px;
}

.team-header .team-icon {
  width: 20px;
  height: 20px;
}

.team-header span {
  color: #ffd56b;
  font-size: 12px;
  font-weight: bold;
}

.player-slots {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.player-slot {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px;
  background: rgba(255,255,255,0.03);
  border-radius: 10px;
  border: 2px solid transparent;
}

.player-slot.filled {
  border-color: rgba(255,213,107,0.3);
}

.player-slot.empty {
  opacity: 0.5;
}

.player-slot .av {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  overflow: hidden;
  background: rgba(255,255,255,0.1);
}

.player-slot .av img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.player-slot .av.empty-slot {
  display: flex;
  align-items: center;
  justify-content: center;
  color: #666;
  font-size: 20px;
}

.player-slot .pi {
  flex: 1;
}

.player-slot .pi b {
  color: #fff;
  font-size: 13px;
}

.player-slot .pi .mut {
  color: #666;
}

.player-slot .badge {
  display: inline-block;
  padding: 2px 6px;
  border-radius: 4px;
  font-size: 9px;
  margin-left: 4px;
}

.player-slot .badge.host {
  background: rgba(255,213,107,0.3);
  color: #ffd56b;
}

.player-slot .badge.ready {
  background: rgba(50,255,100,0.2);
  color: #5f5;
}

.player-slot .status img {
  width: 20px;
  height: 20px;
}

.vs-divider {
  color: #ffd56b;
  font-size: 24px;
  font-weight: bold;
  padding-top: 40px;
}

.spectators-count {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  color: #888;
  font-size: 12px;
  margin-bottom: 16px;
}

.spectators-count img {
  width: 16px;
  height: 16px;
}

.status-area {
  text-align: center;
  margin-bottom: 20px;
}

.s {
  padding: 16px;
  border-radius: 12px;
  font-size: 14px;
}

.s.waiting {
  background: rgba(255,255,255,0.05);
  color: #888;
}

.s.ready {
  background: rgba(50,255,100,0.15);
  color: #5f5;
}

.s.starting, .s.searching {
  background: rgba(255,213,107,0.15);
  color: #ffd56b;
}

.spinner {
  display: inline-block;
  width: 16px;
  height: 16px;
  border: 2px solid #ffd56b;
  border-top-color: transparent;
  border-radius: 50%;
  animation: spin 1s linear infinite;
  margin-right: 8px;
  vertical-align: middle;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.actions {
  display: flex;
  flex-direction: column;
  gap: 12px;
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

.acts {
  display: flex;
  gap: 12px;
  margin-top: 20px;
}

.acts .btn {
  flex: 1;
}
</style>

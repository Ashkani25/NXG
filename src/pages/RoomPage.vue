<template>
  <div class="scr room">
    <div class="bgmagic"></div>
    
    <div class="top">
      <button class="ibtn bk" @click="leave">
        <img src="/assets/nx3/a_left.webp" alt="">
      </button>
      <h2 class="gold">ROOM</h2>
      <div class="sp"></div>
    </div>
    
    <div class="page">
      <!-- Room Code -->
      <div class="room-code">
        <small>ROOM CODE</small>
        <b>{{ match.roomCode }}</b>
        <button class="btn ghost sm" @click="copyCode">
          <img src="/assets/nx3/gear.webp" alt="" style="width:16px">
          COPY
        </button>
      </div>
      
      <!-- Players -->
      <div class="players">
        <div class="player-slot" :class="{ filled: true }">
          <div class="av">
            <img :src="hostAvatar" alt="">
          </div>
          <div class="pi">
            <b>{{ player.profile.name }}</b>
            <span>{{ match.isHost ? 'HOST' : 'PLAYER' }}</span>
          </div>
          <div class="check">
            <img src="/assets/nx3/i_star.webp" alt="">
          </div>
        </div>
        
        <div class="vs">VS</div>
        
        <div class="player-slot" :class="{ filled: !!match.opponent }">
          <div class="av">
            <img v-if="match.opponent" :src="opponentAvatar" alt="">
            <div v-else class="waiting">?</div>
          </div>
          <div class="pi">
            <b>{{ match.opponent?.name || 'Waiting...' }}</b>
            <span v-if="match.opponent">OPPONENT</span>
            <span v-else class="mut">Waiting for player</span>
          </div>
          <div v-if="match.opponent" class="check">
            <img src="/assets/nx3/i_star.webp" alt="">
          </div>
        </div>
      </div>
      
      <!-- Status -->
      <div class="status">
        <div v-if="match.status === 'connecting'" class="s Connecting...">
          <div class="spinner"></div>
          Connecting...
        </div>
        <div v-else-if="match.status === 'waiting'" class="s waiting">
          Waiting for opponent to join...
        </div>
        <div v-else-if="match.status === 'ready'" class="s ready">
          Opponent joined! Starting soon...
        </div>
      </div>
      
      <!-- Start Button (Host only) -->
      <button
        v-if="match.isHost && match.status === 'ready'"
        class="btn gold block cta"
        @click="startMatch"
      >
        START MATCH
      </button>
      
      <!-- Leave Button -->
      <button class="btn dark block" @click="leave">
        LEAVE ROOM
      </button>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { usePlayerStore } from '@/stores/player'
import { useMatchmakingStore } from '@/stores/matchmaking'
import { useGameStore } from '@/stores/game'

const route = useRoute()
const router = useRouter()
const player = usePlayerStore()
const match = useMatchmakingStore()
const game = useGameStore()

const hostAvatar = computed(() => {
  const team = game.TEAMS.find(t => t.id === player.profile.team)
  return team?.src || '/assets/teams/club0.webp'
})

const opponentAvatar = computed(() => {
  if (!match.opponent) return '/assets/teams/club0.webp'
  const team = game.TEAMS[0]
  return team?.src || '/assets/teams/club0.webp'
})

function copyCode() {
  navigator.clipboard.writeText(match.roomCode)
}

async function startMatch() {
  await match.startMatch()
  game.startOnlineMatch({ field: player.profile.equip?.field || 0, ball: player.profile.equip?.ball || 0 })
}

async function leave() {
  await match.leaveRoom()
  router.push('/online')
}
</script>

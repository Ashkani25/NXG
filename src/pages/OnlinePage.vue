<template>
  <div class="scr online">
    <div class="bgmagic"></div>
    
    <div class="top">
      <button class="ibtn bk" @click="$router.back()">
        <img src="/assets/nx3/a_left.webp" alt="">
      </button>
      <h2 class="gold">ONLINE</h2>
      <div class="sp"></div>
    </div>
    
    <div class="page">
      <!-- Username Entry -->
      <div v-if="!player.isOnline && !player.isGuest" class="username-section">
        <div class="card pad">
          <h3>Enter Your Name</h3>
          <p class="mut">This name will be visible to other players</p>
          <input class="inp" v-model="username" placeholder="Your name..." maxlength="16">
          <button class="btn gold block" @click="enterOnline">
            ENTER ONLINE
          </button>
          <button class="btn ghost block" @click="playAsGuest">
            PLAY AS GUEST
          </button>
        </div>
      </div>
      
      <!-- Online Options -->
      <div v-else class="online-menu">
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
        
        <div class="online-cards">
          <div class="oc" @click="createRoom">
            <img src="/assets/nx3/k_team.webp" alt="">
            <b>CREATE ROOM</b>
            <small>Start a new game room</small>
          </div>
          
          <div class="oc" @click="showJoinInput = true">
            <img src="/assets/nx3/c_rankings.webp" alt="">
            <b>JOIN ROOM</b>
            <small>Enter room code</small>
          </div>
        </div>
        
        <button class="btn ghost block" @click="signOut">
          Sign Out
        </button>
      </div>
      
      <!-- Join Room Input -->
      <div v-if="showJoinInput" class="join-modal">
        <div class="card pad">
          <h3>Join Room</h3>
          <input class="inp" v-model="joinCode" placeholder="Enter 6-digit code" maxlength="6">
          <div class="acts">
            <button class="btn dark" @click="showJoinInput = false">Cancel</button>
            <button class="btn gold" @click="joinRoom">Join</button>
          </div>
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
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { usePlayerStore } from '@/stores/player'
import { useMatchmakingStore } from '@/stores/matchmaking'
import { useGameStore } from '@/stores/game'

const router = useRouter()
const player = usePlayerStore()
const match = useMatchmakingStore()
const game = useGameStore()

const username = ref('')
const showJoinInput = ref(false)
const joinCode = ref('')

const teamAvatar = computed(() => {
  const team = game.TEAMS.find(t => t.id === player.profile.team)
  return team?.src || '/assets/teams/club0.webp'
})

async function enterOnline() {
  if (!username.value.trim()) return
  await player.signInOnline(username.value.trim())
}

async function playAsGuest() {
  await player.signInGuest()
}

async function createRoom() {
  try {
    const code = await match.createRoom()
    router.push('/room/' + code)
  } catch (e) {
    alert('Failed to create room: ' + e.message)
  }
}

async function joinRoom() {
  if (!joinCode.value.trim()) return
  try {
    await match.joinRoom(joinCode.value.trim())
    router.push('/room/' + joinCode.value.trim().toUpperCase())
  } catch (e) {
    alert('Failed to join: ' + e.message)
  }
}

function signOut() {
  player.isOnline = false
  player.isGuest = true
}
</script>

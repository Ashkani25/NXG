<template>
  <div class="scr home">
    <!-- Background -->
    <div class="bgmagic"></div>
    
    <!-- Header Bar -->
    <div class="hb">
      <div class="me" @click="$router.push('/team-select')">
        <div class="avw">
          <img class="crw" :src="teamAvatar" alt="">
          <div class="av sm">
            <img :src="teamAvatar" alt="">
          </div>
        </div>
        <div class="mt">
          <b class="nm">{{ player.profile.name }}</b>
          <span class="xpl">Lv. {{ player.profile.level }}</span>
          <div class="bar">
            <i :style="{ width: xpPercent + '%' }"></i>
          </div>
        </div>
      </div>
      
      <div class="cus">
        <div class="cu" @click="$router.push('/settings')">
          <img src="/assets/nx3/coin.webp" alt="">
          <b>{{ player.profile.coins }}</b>
        </div>
        <div class="cu" @click="$router.push('/settings')">
          <img src="/assets/nx3/gem.webp" alt="">
          <b>{{ player.profile.gems }}</b>
        </div>
      </div>
      
      <button class="rb2" @click="$router.push('/settings')">
        <img src="/assets/nx3/gear.webp" alt="">
      </button>
    </div>
    
    <!-- Logo -->
    <div class="logo">
      <img src="/assets/nx3/logo.webp" alt="BERMUDA NXG">
      <small>ONLINE DISC FOOTBALL</small>
    </div>
    
    <!-- Main Menu Cards -->
    <div class="stage">
      <div class="cs">
        <div
          v-for="(card, i) in cards"
          :key="i"
          class="cc"
          :class="{ main: i === 2 }"
          @click="card.action"
        >
          <img :src="'/assets/nx3/' + card.art + '.webp'" :alt="card.t">
          <b>{{ card.t }}</b>
        </div>
      </div>
    </div>
    
    <!-- Bottom Nav -->
    <div class="navbar">
      <button @click="$router.push('/')">
        <img src="/assets/nx3/t_home.webp" alt="">
        <span>HOME</span>
      </button>
      <button @click="$router.push('/team-select')">
        <img src="/assets/nx3/t_user.webp" alt="">
        <span>TEAM</span>
      </button>
      <button class="mid" @click="$router.push('/play')">
        <b>PLAY</b>
      </button>
      <button @click="$router.push('/online')">
        <img src="/assets/nx3/t_trophy.webp" alt="">
        <span>ONLINE</span>
      </button>
      <button @click="$router.push('/settings')">
        <img src="/assets/nx3/gear.webp" alt="">
        <span>SETTINGS</span>
      </button>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { usePlayerStore } from '@/stores/player'
import { useGameStore } from '@/stores/game'

const player = usePlayerStore()
const game = useGameStore()

const teamAvatar = computed(() => {
  const team = game.TEAMS.find(t => t.id === player.profile.team)
  return team?.src || '/assets/teams/club0.webp'
})

const xpPercent = computed(() => {
  const xpNeed = 300 + player.profile.level * 350
  return Math.min(100, (player.profile.xp / xpNeed) * 100)
})

const cards = computed(() => [
  { t: 'QUICK PLAY', art: 'k_ball', action: () => playOffline() },
  { t: 'VS BOT', art: 'c_discs', action: () => playBot() },
  { t: 'PLAY ONLINE', art: 'c_play', action: () => $router.push('/online') },
  { t: 'CHOOSE TEAM', art: 'c_rankings', action: () => $router.push('/team-select') },
  { t: 'SETTINGS', art: 'gear', action: () => $router.push('/settings') },
])

function playOffline() {
  game.startLocalMatch({ field: player.profile.equip?.field || 0, ball: player.profile.equip?.ball || 0 })
}

function playBot() {
  game.startLocalMatch({ mode: 'bot', field: player.profile.equip?.field || 0, ball: player.profile.equip?.ball || 0 })
}
</script>

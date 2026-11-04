<template>
  <div class="scr play">
    <div class="bgmagic"></div>
    
    <div class="top">
      <button class="ibtn bk" @click="$router.back()">
        <img src="/assets/nx3/a_left.webp" alt="">
      </button>
      <h2 class="gold">SELECT MODE</h2>
      <div class="sp"></div>
    </div>
    
    <div class="page">
      <div class="modes">
        <div class="mode-card" @click="startLocal">
          <img src="/assets/nx3/k_ball.webp" alt="">
          <div class="mc">
            <b>LOCAL PLAY</b>
            <small>Play against a friend on this device</small>
          </div>
        </div>
        
        <div class="mode-card" @click="startBot">
          <img src="/assets/nx3/c_discs.webp" alt="">
          <div class="mc">
            <b>VS BOT</b>
            <small>Practice against AI opponent</small>
          </div>
        </div>
        
        <div class="mode-card online" @click="$router.push('/online')">
          <img src="/assets/nx3/c_play.webp" alt="">
          <div class="mc">
            <b>ONLINE</b>
            <small>Play with others online</small>
          </div>
          <div class="tag" v-if="player.isOnline">
            <span class="live"></span>
            LIVE
          </div>
        </div>
      </div>
      
      <div class="sec">FIELD</div>
      <div class="fgrid">
        <div
          v-for="(f, i) in game.FIELDS.slice(0, 8)"
          :key="f.id"
          class="fc"
          :class="{ sel: selectedField === i }"
          @click="selectedField = i"
        >
          <img :src="'/assets/fields/' + f.id + '.webp'" :alt="f.name">
          <b>{{ f.name }}</b>
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
      <button @click="$router.push('/online')">
        <img src="/assets/nx3/t_trophy.webp" alt=""><span>ONLINE</span>
      </button>
      <button @click="$router.push('/settings')">
        <img src="/assets/nx3/gear.webp" alt=""><span>SETTINGS</span>
      </button>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { usePlayerStore } from '@/stores/player'
import { useGameStore } from '@/stores/game'

const player = usePlayerStore()
const game = useGameStore()
const selectedField = ref(0)

function startLocal() {
  game.startLocalMatch({ field: selectedField.value })
}

function startBot() {
  game.startLocalMatch({ mode: 'bot', field: selectedField.value })
}
</script>

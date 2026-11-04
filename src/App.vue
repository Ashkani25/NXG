<template>
  <div id="nx-app" :class="{ 'in-game': gameStore.phase === 'playing' }">
    <!-- Game Canvas Layer -->
    <canvas id="bgc"></canvas>
    <canvas id="game"></canvas>
    <div id="vig"></div>
    
    <!-- HUD Layer (shown during gameplay) -->
    <div id="hud">
      <div class="sb">
        <div class="team" id="t0">
          <img id="i0" alt="">
          <span id="n0"></span>
          <b id="s1">0</b>
        </div>
        <div id="mclk"></div>
        <div id="tmr"><span>15</span></div>
        <div class="team r" id="t1">
          <img id="i1" alt="">
          <span id="n1"></span>
          <b id="s2">0</b>
        </div>
      </div>
      <div id="bubbles"></div>
      <div class="emo" id="emo"></div>
      <div class="hbot" id="hbot"></div>
    </div>
    
    <div class="toast" id="toast"></div>
    <div id="goalfx">
      <img src="/assets/nx3/goal_txt.webp" alt="GOAL">
      <small></small>
    </div>
    
    <!-- UI Layer -->
    <router-view />
    
    <div id="modals"></div>
    <div id="toasts"></div>
  </div>
</template>

<script setup>
import { onMounted } from 'vue'
import { useGameStore } from '@/stores/game'
import { usePlayerStore } from '@/stores/player'
import { GameEngine } from '@/lib/game'

const gameStore = useGameStore()
const playerStore = usePlayerStore()

onMounted(async () => {
  await playerStore.init()
  if (window.NexoraGame) {
    gameStore.setEngine(window.NexoraGame)
  }
})
</script>

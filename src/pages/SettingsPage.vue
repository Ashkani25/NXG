<template>
  <div class="scr settings">
    <div class="bgmagic"></div>
    
    <div class="top">
      <button class="ibtn bk" @click="$router.back()">
        <img src="/assets/nx3/a_left.webp" alt="">
      </button>
      <h2 class="gold">SETTINGS</h2>
      <div class="sp"></div>
    </div>
    
    <div class="page">
      <div class="sec">AUDIO</div>
      <div class="set">
        <img src="/assets/nx3/gear.webp" alt="">
        <span>Sound</span>
        <div class="tgl" :class="{ on: game.SET.snd }" @click="game.SET.snd = game.SET.snd ? 0 : 1"></div>
      </div>
      <div class="set">
        <img src="/assets/nx3/gear.webp" alt="">
        <span>Music</span>
        <div class="tgl" :class="{ on: game.SET.mus }" @click="game.SET.mus = game.SET.mus ? 0 : 1"></div>
      </div>
      <div class="set">
        <img src="/assets/nx3/gear.webp" alt="">
        <span>Vibration</span>
        <div class="tgl" :class="{ on: game.SET.vib }" @click="game.SET.vib = game.SET.vib ? 0 : 1"></div>
      </div>
      
      <div class="sec">GAME</div>
      <div class="set">
        <img src="/assets/nx3/gear.webp" alt="">
        <span>Field: {{ currentField?.name }}</span>
      </div>
      <div class="set">
        <img src="/assets/nx3/gear.webp" alt="">
        <span>Ball: #{{ game.SET.ball }}</span>
      </div>
      
      <div class="sec">ACCOUNT</div>
      <div class="set">
        <img src="/assets/nx3/t_user.webp" alt="">
        <span>{{ player.profile.name }}</span>
      </div>
      <div class="set">
        <img src="/assets/nx3/coin.webp" alt="">
        <span>{{ player.profile.coins }} Coins</span>
      </div>
      <div class="set">
        <img src="/assets/nx3/gem.webp" alt="">
        <span>{{ player.profile.gems }} Gems</span>
      </div>
      
      <div class="sec">VERSION</div>
      <p class="mut" style="padding: 10px;">BERMUDA NXG v1.0.0</p>
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
      <button class="on" @click="$router.push('/settings')">
        <img src="/assets/nx3/gear.webp" alt=""><span>SETTINGS</span>
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

const currentField = computed(() => game.FIELDS[game.SET.fld])
</script>

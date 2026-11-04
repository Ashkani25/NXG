<template>
  <div class="scr team-select">
    <div class="bgmagic"></div>
    
    <div class="top">
      <button class="ibtn bk" @click="$router.back()">
        <img src="/assets/nx3/a_left.webp" alt="">
      </button>
      <h2 class="gold">CHOOSE TEAM</h2>
      <div class="sp"></div>
    </div>
    
    <div class="page">
      <!-- Tabs -->
      <div class="tabs">
        <button
          v-for="(cat, i) in game.CATS"
          :key="cat[0]"
          :class="{ on: selectedCat === i }"
          @click="selectedCat = i"
        >
          {{ cat[1] }}
        </button>
      </div>
      
      <!-- Teams Grid -->
      <div class="tgrid">
        <div
          v-for="team in filteredTeams"
          :key="team.id"
          class="tc"
          :class="{ sel: selectedTeam === team.id }"
          @click="selectTeam(team)"
        >
          <img :src="team.src" :alt="team.name">
          <span>{{ team.name }}</span>
        </div>
      </div>
      
      <!-- Save Button -->
      <button class="btn gold block cta" @click="saveTeam">
        SELECT TEAM
      </button>
    </div>
    
    <!-- Bottom Nav -->
    <div class="navbar">
      <button @click="$router.push('/')">
        <img src="/assets/nx3/t_home.webp" alt=""><span>HOME</span>
      </button>
      <button class="on" @click="$router.push('/team-select')">
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
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { usePlayerStore } from '@/stores/player'
import { useGameStore } from '@/stores/game'

const router = useRouter()
const player = usePlayerStore()
const game = useGameStore()

const selectedCat = ref(0)
const selectedTeam = ref(player.profile.team)

const filteredTeams = computed(() => {
  const catId = game.CATS[selectedCat.value][0]
  return game.TEAMS.filter(t => t.cat === catId)
})

function selectTeam(team) {
  selectedTeam.value = team.id
}

function saveTeam() {
  player.updateProfile({ team: selectedTeam.value, avatar: selectedTeam.value })
  router.back()
}
</script>

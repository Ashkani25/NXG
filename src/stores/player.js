import { defineStore } from 'pinia'
import { ref } from 'vue'
import { supabase } from '@/lib/supabase'

export const usePlayerStore = defineStore('player', () => {
  const profile = ref({
    id: null,
    name: 'Player',
    avatar: 'club0',
    team: 'club0',
    form: 0,
    level: 1,
    xp: 0,
    coins: 1500,
    gems: 20,
    trophies: 0,
    stats: { played: 0, wins: 0, losses: 0, goals: 0, conceded: 0, streak: 0, best: 0 },
    equip: { ball: 4, field: 'stadium' }
  })

  const isOnline = ref(false)
  const isGuest = ref(true)

  async function init() {
    const stored = localStorage.getItem('bermuda_player')
    if (stored) {
      profile.value = { ...profile.value, ...JSON.parse(stored) }
    }
    const { data: { session } } = await supabase.auth.getSession().catch(() => ({ data: { session: null } }))
    if (session) {
      isOnline.value = true
      isGuest.value = false
      await fetchProfile()
    }
  }

  async function fetchProfile() {
    if (!isOnline.value || !profile.value.id) return
    try {
      const { data } = await supabase.from('profiles').select('*').eq('id', profile.value.id).single()
      if (data) {
        profile.value = { ...profile.value, ...data }
        saveLocal()
      }
    } catch (e) {
      console.log('Profile fetch skipped (offline mode)')
    }
  }

  async function signInGuest() {
    profile.value.id = 'guest_' + Math.random().toString(36).slice(2, 10)
    profile.value.name = 'Player' + Math.floor(Math.random() * 999)
    isGuest.value = true
    isOnline.value = false
    saveLocal()
  }

  async function signInOnline(name) {
    profile.value.name = name
    isOnline.value = true
    isGuest.value = false
    saveLocal()
    try {
      await supabase.from('profiles').upsert({
        id: profile.value.id || 'online_' + Date.now(),
        name: name,
        avatar: profile.value.avatar,
        team: profile.value.team,
        updated_at: new Date().toISOString()
      })
    } catch (e) {
      console.log('Online profile save skipped')
    }
  }

  function updateProfile(updates) {
    Object.assign(profile.value, updates)
    saveLocal()
  }

  function saveLocal() {
    localStorage.setItem('bermuda_player', JSON.stringify(profile.value))
  }

  return { profile, isOnline, isGuest, init, fetchProfile, signInGuest, signInOnline, updateProfile, saveLocal }
})

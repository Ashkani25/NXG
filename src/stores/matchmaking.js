import { defineStore } from 'pinia'
import { ref } from 'vue'
import { supabase } from '@/lib/supabase'
import { usePlayerStore } from './player'

export const useMatchmakingStore = defineStore('matchmaking', () => {
  const roomCode = ref(null)
  const roomId = ref(null)
  const isInRoom = ref(false)
  const isHost = ref(false)
  const opponent = ref(null)
  const status = ref('disconnected') // disconnected, connecting, waiting, ready, playing
  const channel = ref(null)

  function generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    let c = ''
    for (let i = 0; i < 6; i++) c += chars[Math.floor(Math.random() * chars.length)]
    return c
  }

  async function createRoom() {
    const player = usePlayerStore()
    status.value = 'connecting'
    roomCode.value = generateCode()
    isHost.value = true

    try {
      const { data, error } = await supabase
        .from('rooms')
        .insert({
          code: roomCode.value,
          host_id: player.profile.id,
          host_name: player.profile.name,
          status: 'waiting'
        })
        .select()
        .single()

      if (error) throw error
      roomId.value = data.id
      isInRoom.value = true
      status.value = 'waiting'
      subscribeToRoom()
      return roomCode.value
    } catch (e) {
      console.error('Create room failed:', e)
      status.value = 'disconnected'
      throw e
    }
  }

  async function joinRoom(code) {
    const player = usePlayerStore()
    status.value = 'connecting'

    try {
      const { data: room, error } = await supabase
        .from('rooms')
        .select('*')
        .eq('code', code.toUpperCase())
        .single()

      if (error || !room) throw new Error('Room not found')
      if (room.status !== 'waiting') throw new Error('Room is full')

      roomCode.value = code.toUpperCase()
      roomId.value = room.id
      isHost.value = false
      isInRoom.value = true

      await supabase
        .from('rooms')
        .update({ guest_id: player.profile.id, guest_name: player.profile.name, status: 'ready' })
        .eq('id', room.id)

      opponent.value = { id: room.host_id, name: room.host_name }
      status.value = 'ready'
      subscribeToRoom()
    } catch (e) {
      status.value = 'disconnected'
      throw e
    }
  }

  function subscribeToRoom() {
    const player = usePlayerStore()
    channel.value = supabase
      .channel('room_' + roomId.value)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'rooms', filter: 'id=eq.' + roomId.value }, (payload) => {
        const r = payload.new
        if (r.status === 'ready' && !isHost.value) {
          opponent.value = { id: r.guest_id, name: r.guest_name }
          status.value = 'ready'
        }
        if (r.status === 'playing') {
          opponent.value = isHost.value ? { id: r.guest_id, name: r.guest_name } : { id: r.host_id, name: r.host_name }
          status.value = 'playing'
        }
      })
      .subscribe()
  }

  async function startMatch() {
    if (!isHost.value || !roomId.value) return
    await supabase.from('rooms').update({ status: 'playing' }).eq('id', roomId.value)
    status.value = 'playing'
  }

  async function leaveRoom() {
    if (channel.value) {
      await supabase.removeChannel(channel.value)
      channel.value = null
    }
    if (roomId.value) {
      try {
        if (isHost.value) {
          await supabase.from('rooms').delete().eq('id', roomId.value)
        } else {
          await supabase.from('rooms').update({ guest_id: null, guest_name: null, status: 'waiting' }).eq('id', roomId.value)
        }
      } catch (e) {}
    }
    reset()
  }

  function reset() {
    roomCode.value = null
    roomId.value = null
    isInRoom.value = false
    isHost.value = false
    opponent.value = null
    status.value = 'disconnected'
    channel.value = null
  }

  return { roomCode, roomId, isInRoom, isHost, opponent, status, createRoom, joinRoom, startMatch, leaveRoom, reset }
})

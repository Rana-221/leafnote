<template>
  <ModalDialog
    :open="open"
    :title="localGroup?.name || group?.name || '群组'"
    subtitle="成员、邀请与实名可见性设置"
    size="lg"
    @close="$emit('close')"
  >
    <div v-if="loading" class="dialog-loading">
      <AppIcon name="loader" :size="20" class="spin" /> 正在读取群组…
    </div>

    <template v-else>
      <div class="group-tabs" role="tablist" aria-label="群组管理">
        <button
          type="button"
          role="tab"
          :aria-selected="tab === 'members'"
          :class="{ active: tab === 'members' }"
          @click="tab = 'members'"
        >
          <AppIcon name="users" :size="16" /> 成员
          <span class="tab-count">{{ members.length }}</span>
        </button>
        <button
          type="button"
          role="tab"
          :aria-selected="tab === 'invites'"
          :class="{ active: tab === 'invites' }"
          @click="tab = 'invites'"
        >
          <AppIcon name="qr-code" :size="16" /> 邀请
        </button>
        <button
          type="button"
          role="tab"
          :aria-selected="tab === 'settings'"
          :class="{ active: tab === 'settings' }"
          @click="tab = 'settings'"
        >
          <AppIcon name="settings" :size="16" /> 设置
        </button>
      </div>

      <!-- Members -->
      <section v-if="tab === 'members'" class="group-section">
        <div class="group-meta-row">
          <span><AppIcon name="users" :size="15" /> {{ members.length }} 位组员</span>
          <span class="role-pill" :class="`role-${myRole}`">{{ roleLabel(myRole) }}</span>
        </div>
        <ul class="member-list">
          <li v-for="member in members" :key="member.user_id" class="member-item">
            <UserAvatar :profile="member.profile" :size="40" />
            <div class="member-info">
              <div class="member-name-row">
                <strong>{{ member.profile?.username || '未知用户' }}</strong>
                <span v-if="member.user_id === localGroup?.owner_id" class="owner-badge">
                  <AppIcon name="crown" :size="12" /> 群主
                </span>
                <span v-else-if="member.role === 'admin'" class="admin-badge">管理员</span>
                <span v-if="member.user_id === currentUserId" class="me-badge">我</span>
              </div>
              <div class="member-realname">
                <AppIcon name="shield" :size="13" />
                <template v-if="realNameVisibleFor(member.user_id)">
                  <span v-if="identityMap[member.user_id]">
                    {{ identityMap[member.user_id].real_name }}
                    <span class="id-number">· {{ identityMap[member.user_id].id_number }}</span>
                  </span>
                  <span v-else class="muted">未填写实名信息</span>
                </template>
                <span v-else class="muted">{{ hiddenRealNameReason }}</span>
              </div>
            </div>
            <div v-if="canManageMember(member)" class="member-actions">
              <button
                v-if="isOwner && member.user_id !== localGroup?.owner_id"
                class="icon-btn"
                type="button"
                :title="member.role === 'admin' ? '设为普通组员' : '设为管理员'"
                @click="toggleRole(member)"
              >
                <AppIcon :name="member.role === 'admin' ? 'chevron-down' : 'crown'" :size="16" />
              </button>
              <button
                class="icon-btn danger-hover"
                type="button"
                title="移出群组"
                @click="removeMember(member)"
              >
                <AppIcon name="x" :size="16" />
              </button>
            </div>
          </li>
        </ul>
        <div class="info-box">
          <AppIcon name="shield" :size="17" />
          <div>
            <strong>实名信息按群组隔离</strong>
            <p>
              当前可见范围：{{ visibilityLabel(localGroup?.real_name_visibility) }}。组外用户无法读取实名数据，
              此限制由数据库 RLS 与群组级 RPC 共同执行。
            </p>
          </div>
        </div>
      </section>

      <!-- Invites -->
      <section v-else-if="tab === 'invites'" class="group-section">
        <div class="invite-intro">
          <div>
            <h3>邀请新组员</h3>
            <p>管理员和普通组员都可以生成邀请码与二维码。邀请码可随时撤销。</p>
          </div>
          <span class="privacy-chip"><AppIcon name="key" :size="13" /> 组内成员均可邀请</span>
        </div>

        <form class="invite-create" @submit.prevent="createInvite">
          <label class="field">
            <span>有效期</span>
            <select v-model.number="inviteHours">
              <option :value="24">1 天</option>
              <option :value="168">7 天</option>
              <option :value="720">30 天</option>
              <option :value="8760">365 天</option>
            </select>
          </label>
          <label class="field">
            <span>最多使用次数</span>
            <input
              v-model="inviteMaxUses"
              type="number"
              min="1"
              max="10000"
              inputmode="numeric"
              placeholder="留空 = 不限"
            />
          </label>
          <button class="btn btn-primary" type="submit" :disabled="inviteBusy">
            <AppIcon v-if="inviteBusy" name="loader" :size="16" class="spin" />
            {{ inviteBusy ? '生成中…' : '生成邀请码' }}
          </button>
        </form>

        <div v-if="selectedInvite" class="invite-qr-panel">
          <div class="invite-qr-code" v-html="selectedQrSvg"></div>
          <div class="invite-qr-info">
            <span class="eyebrow">SCAN TO JOIN</span>
            <strong>{{ localGroup?.name }}</strong>
            <p>让新成员用手机扫码，登录后即可加入群组。</p>
            <div class="invite-code-display">{{ selectedInvite.code }}</div>
            <div class="invite-link-row">
              <input :value="inviteLink(selectedInvite)" readonly />
              <button class="btn btn-secondary btn-sm" type="button" @click="copyInviteLink(selectedInvite)">
                <AppIcon name="copy" :size="14" /> 复制链接
              </button>
            </div>
            <button class="text-link" type="button" @click="selectedInvite = null">收起二维码</button>
          </div>
        </div>

        <div v-if="invites.length" class="invite-list">
          <div v-for="invite in invites" :key="invite.id" class="invite-item" :class="{ inactive: inviteStatus(invite).key !== 'active' }">
            <div class="invite-main">
              <div class="invite-code">{{ invite.code }}</div>
              <div class="invite-meta">
                <span class="status-pill" :class="`status-${inviteStatus(invite).key}`">{{ inviteStatus(invite).label }}</span>
                <span>{{ invite.uses }}{{ invite.max_uses ? ` / ${invite.max_uses}` : '' }} 次使用</span>
                <span v-if="invite.expires_at">至 {{ formatDate(invite.expires_at) }}</span>
                <span>由 {{ creatorName(invite) }} 创建</span>
              </div>
            </div>
            <div class="invite-actions">
              <button class="icon-btn" type="button" title="复制邀请码" @click="copyCode(invite)">
                <AppIcon name="copy" :size="16" />
              </button>
              <button
                v-if="inviteStatus(invite).key === 'active'"
                class="icon-btn"
                type="button"
                title="显示二维码"
                @click="selectedInvite = invite"
              >
                <AppIcon name="qr-code" :size="16" />
              </button>
              <button
                v-if="canRevoke(invite) && !invite.revoked"
                class="icon-btn danger-hover"
                type="button"
                title="撤销邀请码"
                @click="revokeInvite(invite)"
              >
                <AppIcon name="x" :size="16" />
              </button>
            </div>
          </div>
        </div>
        <div v-else class="empty-inline">
          <AppIcon name="qr-code" :size="28" />
          <p>还没有邀请码。生成一个分享给新组员吧。</p>
        </div>
      </section>

      <!-- Settings -->
      <section v-else class="group-section">
        <div class="settings-block">
          <div class="section-title-row">
            <h3>群组资料</h3>
            <span v-if="!isAdmin" class="optional-chip">仅管理员可编辑</span>
          </div>
          <label class="field">
            <span>群组名称</span>
            <input v-model="settingsName" type="text" maxlength="60" :disabled="!isAdmin" />
          </label>
          <div class="field">
            <span>实名信息可见性</span>
            <div class="visibility-options">
              <label
                v-for="option in visibilityOptions"
                :key="option.value"
                class="visibility-option"
                :class="{ selected: settingsVisibility === option.value, disabled: !isAdmin }"
              >
                <input
                  v-model="settingsVisibility"
                  type="radio"
                  :value="option.value"
                  :disabled="!isAdmin"
                />
                <span class="visibility-radio"></span>
                <span>
                  <strong>{{ option.label }}</strong>
                  <small>{{ option.description }}</small>
                </span>
              </label>
            </div>
          </div>
          <div v-if="isAdmin" class="settings-actions">
            <button class="btn btn-primary" type="button" :disabled="settingsBusy" @click="saveSettings">
              <AppIcon v-if="settingsBusy" name="loader" :size="16" class="spin" />
              {{ settingsBusy ? '保存中…' : '保存设置' }}
            </button>
          </div>
        </div>

        <div class="settings-block">
          <h3>转让群组</h3>
          <p class="section-description">
            群主可以将群组转让给任意一位组员。转让后，原群主会变为普通组员，新群主获得管理员权限。
          </p>
          <div v-if="isOwner" class="transfer-row">
            <select v-model="transferTarget">
              <option value="">选择一位组员</option>
              <option
                v-for="member in members.filter((item) => item.user_id !== currentUserId)"
                :key="member.user_id"
                :value="member.user_id"
              >
                {{ member.profile?.username || '未知用户' }}
              </option>
            </select>
            <button class="btn btn-secondary" type="button" :disabled="!transferTarget || transferBusy" @click="transferGroup">
              {{ transferBusy ? '转让中…' : '转让群组' }}
            </button>
          </div>
          <p v-else class="field-hint">只有群主可以转让群组。</p>
        </div>

        <div class="settings-block danger-zone">
          <h3>退出群组</h3>
          <p class="section-description">
            退出后将无法访问该群组的任何笔记、文件夹与成员信息。你创建的笔记仍会留在群组中。
          </p>
          <button
            class="btn btn-danger-outline"
            type="button"
            :disabled="isOwner"
            @click="leaveGroup"
          >
            {{ isOwner ? '群主需先转让群组' : '退出群组' }}
          </button>
        </div>
      </section>
    </template>
  </ModalDialog>
</template>

<script setup>
import { computed, ref, watch } from 'vue'
import AppIcon from './AppIcon.vue'
import ModalDialog from './ModalDialog.vue'
import UserAvatar from './UserAvatar.vue'
import { supabase } from '../lib/supabase'
import { copyText, errorMessage, formatDate } from '../lib/utils'
import { makeQrSvg } from '../lib/qr'
import { toast } from '../lib/toast'

const props = defineProps({
  open: { type: Boolean, default: false },
  group: { type: Object, required: true },
  session: { type: Object, required: true },
  initialTab: { type: String, default: 'members' }
})
const emit = defineEmits(['close', 'changed', 'left'])

const loading = ref(true)
const tab = ref('members')
const localGroup = ref({ ...props.group })
const members = ref([])
const invites = ref([])
const identityMap = ref({})

const settingsName = ref('')
const settingsVisibility = ref('members')
const settingsBusy = ref(false)
const transferTarget = ref('')
const transferBusy = ref(false)

const inviteHours = ref(168)
const inviteMaxUses = ref('')
const inviteBusy = ref(false)
const selectedInvite = ref(null)

const currentUserId = computed(() => props.session.user.id)
const ownMember = computed(() => members.value.find((member) => member.user_id === currentUserId.value))
const myRole = computed(() => ownMember.value?.role || 'member')
const isAdmin = computed(() => myRole.value === 'admin')
const isOwner = computed(() => localGroup.value?.owner_id === currentUserId.value)
const hiddenRealNameReason = computed(() => {
  if (localGroup.value?.real_name_visibility === 'off') return '群组已关闭实名展示'
  if (localGroup.value?.real_name_visibility === 'admins' && !isAdmin.value) return '仅管理员可见'
  return '未公开'
})

const visibilityOptions = [
  { value: 'members', label: '全部组员可见', description: '同组任何成员都能查看实名信息。' },
  { value: 'admins', label: '仅管理员可见', description: '普通组员看不到，管理员可查看。' },
  { value: 'off', label: '关闭展示', description: '组内也不展示，仅本人可查看和修改。' }
]

const selectedQrSvg = computed(() => {
  if (!selectedInvite.value) return ''
  try {
    return makeQrSvg(inviteLink(selectedInvite.value))
  } catch {
    return ''
  }
})

watch(
  () => props.open,
  async (open) => {
    if (!open) return
    tab.value = ['members', 'invites', 'settings'].includes(props.initialTab) ? props.initialTab : 'members'
    selectedInvite.value = null
    localGroup.value = { ...props.group }
    await loadAll()
  }
)

async function loadAll() {
  loading.value = true
  try {
    const groupQuery = supabase.from('groups').select('*').eq('id', props.group.id).single()
    const memberQuery = supabase
      .from('group_members')
      .select('user_id, role, joined_at')
      .eq('group_id', props.group.id)
      .order('joined_at', { ascending: true })
    const inviteQuery = supabase
      .from('invites')
      .select('*')
      .eq('group_id', props.group.id)
      .order('created_at', { ascending: false })

    const [groupResult, memberResult, inviteResult] = await Promise.all([
      groupQuery,
      memberQuery,
      inviteQuery
    ])
    if (groupResult.error) throw groupResult.error
    if (memberResult.error) throw memberResult.error
    if (inviteResult.error) throw inviteResult.error

    localGroup.value = groupResult.data
    settingsName.value = groupResult.data.name
    settingsVisibility.value = groupResult.data.real_name_visibility
    invites.value = inviteResult.data || []

    const memberRows = memberResult.data || []
    const memberIds = memberRows.map((row) => row.user_id)
    let profileMap = {}
    if (memberIds.length) {
      const { data: profiles, error: profileError } = await supabase
        .from('profiles')
        .select('id, username, avatar_path')
        .in('id', memberIds)
      if (profileError) throw profileError
      profileMap = Object.fromEntries((profiles || []).map((profile) => [profile.id, profile]))
    }
    members.value = memberRows.map((row) => ({
      ...row,
      profile: profileMap[row.user_id] || { id: row.user_id, username: '未知用户', avatar_path: null }
    }))

    const { data: identities, error: identityError } = await supabase.rpc(
      'ln_get_group_real_identities',
      { p_group_id: props.group.id }
    )
    if (identityError) {
      identityMap.value = {}
    } else {
      identityMap.value = Object.fromEntries((identities || []).map((item) => [item.user_id, item]))
    }
  } catch (error) {
    toast.error(errorMessage(error, '群组信息加载失败'))
  } finally {
    loading.value = false
  }
}

function roleLabel(role) {
  return role === 'admin' ? '管理员' : '普通组员'
}

function visibilityLabel(value) {
  return value === 'admins' ? '仅管理员' : value === 'off' ? '已关闭' : '全部组员'
}

function realNameVisibleFor(userId) {
  if (!identityMap.value[userId]) {
    return localGroup.value?.real_name_visibility === 'members' ||
      (localGroup.value?.real_name_visibility === 'admins' && isAdmin.value)
  }
  return true
}

function canManageMember(member) {
  if (!isAdmin.value) return false
  if (member.user_id === currentUserId.value) return false
  if (member.user_id === localGroup.value?.owner_id) return false
  if (member.role === 'admin' && !isOwner.value) return false
  return true
}

async function toggleRole(member) {
  const nextRole = member.role === 'admin' ? 'member' : 'admin'
  const label = nextRole === 'admin' ? '管理员' : '普通组员'
  if (!window.confirm(`确定将「${member.profile?.username}」设为${label}吗？`)) return
  try {
    const { error } = await supabase.rpc('ln_set_member_role', {
      p_group_id: props.group.id,
      p_user_id: member.user_id,
      p_role: nextRole
    })
    if (error) throw error
    toast.success('角色已更新')
    await loadAll()
    emit('changed')
  } catch (error) {
    toast.error(errorMessage(error, '角色更新失败'))
  }
}

async function removeMember(member) {
  if (!window.confirm(`确定将「${member.profile?.username}」移出群组吗？对方将立即失去所有访问权限。`)) return
  try {
    const { error } = await supabase.rpc('ln_remove_group_member', {
      p_group_id: props.group.id,
      p_user_id: member.user_id
    })
    if (error) throw error
    toast.success('已移出群组')
    await loadAll()
    emit('changed')
  } catch (error) {
    toast.error(errorMessage(error, '移除失败'))
  }
}

function inviteStatus(invite) {
  if (invite.revoked) return { key: 'revoked', label: '已撤销' }
  if (invite.expires_at && new Date(invite.expires_at) <= new Date()) {
    return { key: 'expired', label: '已过期' }
  }
  if (invite.max_uses && invite.uses >= invite.max_uses) {
    return { key: 'exhausted', label: '已用完' }
  }
  return { key: 'active', label: '有效' }
}

function creatorName(invite) {
  return members.value.find((member) => member.user_id === invite.created_by)?.profile?.username || '前成员'
}

function canRevoke(invite) {
  return isAdmin.value || invite.created_by === currentUserId.value
}

function inviteLink(invite) {
  const url = new URL(window.location.origin + window.location.pathname)
  url.search = ''
  url.hash = ''
  url.searchParams.set('invite', invite.code)
  return url.toString()
}

async function copyCode(invite) {
  try {
    await copyText(invite.code)
    toast.success('邀请码已复制')
  } catch {
    toast.error('复制失败，请手动选择')
  }
}

async function copyInviteLink(invite) {
  try {
    await copyText(inviteLink(invite))
    toast.success('邀请链接已复制')
  } catch {
    toast.error('复制失败，请手动复制')
  }
}

async function createInvite() {
  inviteBusy.value = true
  try {
    const maxUses = inviteMaxUses.value === '' ? null : Number(inviteMaxUses.value)
    if (maxUses !== null && (!Number.isInteger(maxUses) || maxUses < 1)) {
      throw new Error('最多使用次数需要是正整数，或留空')
    }
    const { data, error } = await supabase.rpc('ln_create_invite', {
      p_group_id: props.group.id,
      p_expires_hours: inviteHours.value,
      p_max_uses: maxUses
    })
    if (error) throw error
    invites.value = [data, ...invites.value]
    selectedInvite.value = data
    inviteMaxUses.value = ''
    toast.success('邀请码已生成')
  } catch (error) {
    toast.error(errorMessage(error, '邀请码生成失败'))
  } finally {
    inviteBusy.value = false
  }
}

async function revokeInvite(invite) {
  if (!window.confirm(`撤销邀请码 ${invite.code}？撤销后无法再用于加入群组。`)) return
  try {
    const { error } = await supabase.rpc('ln_revoke_invite', { p_invite_id: invite.id })
    if (error) throw error
    invite.revoked = true
    if (selectedInvite.value?.id === invite.id) selectedInvite.value = null
    toast.success('邀请码已撤销')
  } catch (error) {
    toast.error(errorMessage(error, '撤销失败'))
  }
}

async function saveSettings() {
  const name = settingsName.value.trim()
  if (!name) {
    toast.error('群组名称不能为空')
    return
  }
  settingsBusy.value = true
  try {
    const { error } = await supabase.rpc('ln_update_group_settings', {
      p_group_id: props.group.id,
      p_name: name,
      p_real_name_visibility: settingsVisibility.value
    })
    if (error) throw error
    localGroup.value = {
      ...localGroup.value,
      name,
      real_name_visibility: settingsVisibility.value
    }
    await loadAll()
    emit('changed')
    toast.success('群组设置已保存')
  } catch (error) {
    toast.error(errorMessage(error, '保存失败'))
  } finally {
    settingsBusy.value = false
  }
}

async function transferGroup() {
  if (!transferTarget.value) return
  const target = members.value.find((member) => member.user_id === transferTarget.value)
  if (!window.confirm(`确定把群组转让给「${target?.profile?.username}」吗？你将变为普通组员。`)) return
  transferBusy.value = true
  try {
    const { error } = await supabase.rpc('ln_transfer_group', {
      p_group_id: props.group.id,
      p_new_owner_id: transferTarget.value
    })
    if (error) throw error
    transferTarget.value = ''
    await loadAll()
    emit('changed')
    toast.success('群组已转让')
  } catch (error) {
    toast.error(errorMessage(error, '转让失败'))
  } finally {
    transferBusy.value = false
  }
}

async function leaveGroup() {
  if (!window.confirm(`确定退出「${localGroup.value?.name}」吗？退出后将无法访问该群组的数据。`)) return
  try {
    const { error } = await supabase.rpc('ln_leave_group', { p_group_id: props.group.id })
    if (error) throw error
    toast.success('已退出群组')
    emit('left', props.group.id)
    emit('close')
  } catch (error) {
    toast.error(errorMessage(error, '退出失败'))
  }
}
</script>

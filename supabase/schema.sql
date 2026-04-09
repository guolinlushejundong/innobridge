-- InnoBridge / InnoLink — Supabase 表结构（在 SQL Editor 中执行，或作为 migration）
-- 说明：
-- 1) 前端使用「用户名 + 密码」时，会将邮箱合成为：小写用户名 + '@innolink.local'，请在 Authentication → Providers → Email 中关闭「Confirm email」以便本地快速测试（生产环境建议改为真实邮箱并开启验证）。
-- 2) 附件当前存在 posts.meta JSON 里（base64），大文件请改用 Supabase Storage + 仅存路径。
-- 3) posts 的「任意登录用户可 UPDATE」策略便于 NDA/下载申请等非作者更新 meta；上线前建议改为 RPC（security definer）或拆表。

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- 用户公开资料（与 auth.users 一对一）
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text unique not null,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles_select_all"
  on public.profiles for select
  using (true);

create policy "profiles_insert_own"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- 帖子（项目 / 创意 / 需求）
-- meta JSON 建议字段：
--   attachments: [{ name, type, size, dataUrl }]
--   allow_download_all: boolean
--   download_requests: string[]  （用户名）
--   approved_users: string[]
--   nda_signed_users: string[]
--   nda_sign_logs: [{ user, ts }]
-- ---------------------------------------------------------------------------
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  author_name text not null,
  title text not null,
  category text not null,
  description text not null,
  post_type text not null check (post_type in ('idea', 'demand')),
  badge text,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists posts_created_at_idx on public.posts (created_at desc);
create index if not exists posts_author_id_idx on public.posts (author_id);

alter table public.posts enable row level security;

create policy "posts_select_all"
  on public.posts for select
  using (true);

create policy "posts_insert_authenticated"
  on public.posts for insert
  with check (auth.role() = 'authenticated' and auth.uid() = author_id);

create policy "posts_update_author"
  on public.posts for update
  using (auth.uid() = author_id);

-- 允许已登录用户更新任意帖子（用于浏览者写 NDA / 下载申请等 meta）
-- TODO: 生产环境请改为 RPC 或独立表 + 严格 RLS
create policy "posts_update_authenticated_meta"
  on public.posts for update
  to authenticated
  using (true)
  with check (true);

create policy "posts_delete_author"
  on public.posts for delete
  using (auth.uid() = author_id);

-- ---------------------------------------------------------------------------
-- 会话（全局一条：对方昵称 + 项目标题 唯一）
-- ---------------------------------------------------------------------------
create table if not exists public.chats (
  id uuid primary key default gen_random_uuid(),
  peer_display_name text not null,
  project_title text not null,
  role text not null default '',
  online boolean not null default false,
  unread_count int not null default 0,
  created_at timestamptz not null default now(),
  unique (peer_display_name, project_title)
);

alter table public.chats enable row level security;

create policy "chats_select_all"
  on public.chats for select
  using (true);

create policy "chats_insert_authenticated"
  on public.chats for insert
  with check (auth.role() = 'authenticated');

create policy "chats_update_authenticated"
  on public.chats for update
  to authenticated
  using (true)
  with check (true);

-- ---------------------------------------------------------------------------
-- 聊天消息
-- ---------------------------------------------------------------------------
create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  sender_display_name text not null,
  body text not null,
  read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists chat_messages_chat_id_idx on public.chat_messages (chat_id, created_at);

alter table public.chat_messages enable row level security;

create policy "chat_messages_select_all"
  on public.chat_messages for select
  using (true);

create policy "chat_messages_insert_authenticated"
  on public.chat_messages for insert
  with check (auth.role() = 'authenticated');

create policy "chat_messages_update_authenticated"
  on public.chat_messages for update
  to authenticated
  using (true)
  with check (true);

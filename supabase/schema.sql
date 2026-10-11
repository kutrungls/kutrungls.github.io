-- Nhà Tiger: tạo bảng đơn, quyền gửi đơn công khai, quyền xem/sửa dành cho email quản lý.
-- Thay owner@example.com bằng email quản lý TRƯỚC KHI chạy SQL.

create extension if not exists pgcrypto;

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  table_code text not null check (table_code ~ '^[0-9]{1,3}$'),
  items jsonb not null check (
    case when jsonb_typeof(items) = 'array'
      then jsonb_array_length(items) between 1 and 30
      else false
    end
  ),
  total integer not null check (total > 0),
  note text not null default '' check (char_length(note) <= 500),
  status text not null default 'Mới' check (status in ('Mới', 'Đang làm', 'Đã xong')),
  created_at timestamptz not null default now()
);

create index if not exists orders_created_at_idx on public.orders (created_at desc);

alter table public.orders enable row level security;
grant usage on schema public to anon, authenticated;
revoke all on public.orders from anon, authenticated;
grant insert (table_code, items, total, note, status) on public.orders to anon, authenticated;
grant select (id, table_code, items, total, note, status, created_at) on public.orders to authenticated;
grant update (status) on public.orders to authenticated;

drop policy if exists "Guests can send new orders" on public.orders;
create policy "Guests can send new orders"
  on public.orders for insert to anon, authenticated
  with check (
    status = 'Mới'
    and table_code ~ '^[0-9]{1,3}$'
    and case when jsonb_typeof(items) = 'array'
      then jsonb_array_length(items) between 1 and 30
      else false
    end
    and total > 0
    and char_length(note) <= 500
    and not exists (
      select 1 from jsonb_array_elements(items) as line(value)
      where coalesce(line.value ->> 'name', '') = ''
        or coalesce(line.value ->> 'qty', '') !~ '^[0-9]{1,3}$'
        or coalesce(line.value ->> 'price', '') !~ '^[0-9]{1,9}$'
        or (line.value ->> 'qty')::bigint not between 1 and 50
        or (line.value ->> 'price')::bigint not between 1 and 10000000
    )
    and total = coalesce((
      select sum((line.value ->> 'qty')::bigint * (line.value ->> 'price')::bigint)
      from jsonb_array_elements(items) as line(value)
    ), 0)
  );

drop policy if exists "Only restaurant manager can view orders" on public.orders;
create policy "Only restaurant manager can view orders"
  on public.orders for select to authenticated
  using (lower(auth.jwt() ->> 'email') = lower('owner@example.com'));

drop policy if exists "Only restaurant manager can update orders" on public.orders;
create policy "Only restaurant manager can update orders"
  on public.orders for update to authenticated
  using (lower(auth.jwt() ->> 'email') = lower('owner@example.com'))
  with check (lower(auth.jwt() ->> 'email') = lower('owner@example.com'));

-- Bật đồng bộ thời gian thực cho trang quản lý.
do $$
begin
  alter publication supabase_realtime add table public.orders;
exception when duplicate_object then
  null;
end $$;

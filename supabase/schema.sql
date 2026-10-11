-- Nhà Tiger: tạo bảng đơn, quyền gửi đơn công khai, quyền xem/sửa dành cho email quản lý.
-- Email tài khoản quản lý Nhà Tiger đã cấu hình sẵn.

create extension if not exists pgcrypto;

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_token uuid not null default gen_random_uuid(),
  table_code text not null check (table_code ~ '^[0-9]{1,3}$'),
  items jsonb not null check (
    case when jsonb_typeof(items) = 'array'
      then jsonb_array_length(items) between 1 and 30
      else false
    end
  ),
  total integer not null check (total > 0),
  note text not null default '' check (char_length(note) <= 500),
  status text not null default 'new' check (status in ('new', 'processing', 'done')),
  created_at timestamptz not null default now()
);

-- Nâng cấp an toàn cho project đã tạo bảng orders theo bản trước.
alter table public.orders add column if not exists customer_token uuid;
alter table public.orders alter column customer_token set default gen_random_uuid();
update public.orders set customer_token = gen_random_uuid() where customer_token is null;
alter table public.orders alter column customer_token set not null;
alter table public.orders alter column status set default 'new';
alter table public.orders drop constraint if exists orders_status_check;
update public.orders set status = case status
  when 'Mới' then 'new'
  when 'Đang làm' then 'processing'
  when 'Đã xong' then 'done'
  else status
end;
alter table public.orders add constraint orders_status_check check (status in ('new', 'processing', 'done'));

create index if not exists orders_created_at_idx on public.orders (created_at desc);

alter table public.orders enable row level security;
grant usage on schema public to anon, authenticated;
revoke all on public.orders from anon, authenticated;
grant insert (id, customer_token, table_code, items, total, note, status) on public.orders to anon, authenticated;
grant select (id, table_code, items, total, note, status, created_at) on public.orders to authenticated;
grant update (status) on public.orders to authenticated;

drop policy if exists "Guests can send new orders" on public.orders;
create policy "Guests can send new orders"
  on public.orders for insert to anon, authenticated
  with check (
    status = 'new'
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
  using (lower(auth.jwt() ->> 'email') = lower('kutrungls@gmail.com'));

drop policy if exists "Only restaurant manager can update orders" on public.orders;
create policy "Only restaurant manager can update orders"
  on public.orders for update to authenticated
  using (lower(auth.jwt() ->> 'email') = lower('kutrungls@gmail.com'))
  with check (lower(auth.jwt() ->> 'email') = lower('kutrungls@gmail.com'));

-- Bật đồng bộ thời gian thực cho trang quản lý.
do $$
begin
  alter publication supabase_realtime add table public.orders;
exception when duplicate_object then
  null;
end $$;

-- Khách chỉ tra được trạng thái của đơn khi biết cả ID và mã bí mật của chính đơn đó.
create or replace function public.get_customer_order_status(p_order_id uuid, p_customer_token uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select o.status
  from public.orders as o
  where o.id = p_order_id and o.customer_token = p_customer_token
  limit 1;
$$;
revoke all on function public.get_customer_order_status(uuid, uuid) from public;
grant execute on function public.get_customer_order_status(uuid, uuid) to anon, authenticated;

-- Gửi riêng trạng thái đơn qua topic có customer_token ngẫu nhiên; không phát món/giá/đơn khác.
create or replace function public.broadcast_customer_order_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status is distinct from old.status then
    begin
      perform realtime.send(
        jsonb_build_object('order_id', new.id::text, 'status', new.status),
        'order_status',
        'nhatiger-order:' || new.id::text || ':' || new.customer_token::text,
        false
      );
    exception when others then
      raise warning 'Realtime status broadcast failed for order %: %', new.id, sqlerrm;
    end;
  end if;
  return new;
end;
$$;
revoke all on function public.broadcast_customer_order_status() from public;
drop trigger if exists orders_broadcast_customer_status on public.orders;
create trigger orders_broadcast_customer_status
  after update of status on public.orders
  for each row execute function public.broadcast_customer_order_status();

-- Chạy trên project Nhà Tiger đã có bảng orders.
-- Có thể chạy lại an toàn để bổ sung trạng thái cancelled và giữ theo dõi trạng thái riêng cho khách.

create extension if not exists pgcrypto;

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
  when 'Đã hủy' then 'cancelled'
  else status
end;
alter table public.orders add constraint orders_status_check check (status in ('new', 'processing', 'done', 'cancelled'));

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

-- Khách dùng RPC này với ID + token ngẫu nhiên chỉ lưu trên điện thoại gửi đơn.
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

-- Phát riêng trạng thái đơn qua topic có token ngẫu nhiên, không gửi món/giá hay đơn khác.
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

-- Kích hoạt UPDATE realtime đang dùng cho trang quản lý (an toàn chạy lại).
do $$
begin
  alter publication supabase_realtime add table public.orders;
exception when duplicate_object then
  null;
end $$;

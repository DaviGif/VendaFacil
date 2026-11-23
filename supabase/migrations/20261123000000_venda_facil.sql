create table public.stores (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 100)
);

create table public.members (
  store_id uuid not null references public.stores,
  user_id uuid not null references auth.users on delete cascade,
  role text not null check (role in ('admin', 'operator')),
  primary key (store_id, user_id)
);
create index members_user on public.members (user_id);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores,
  name text not null check (length(trim(name)) between 1 and 120),
  code text not null check (length(trim(code)) between 1 and 40),
  price_cents integer not null check (price_cents > 0),
  stock integer not null check (stock >= 0),
  min_stock integer not null check (min_stock >= 0),
  unique (store_id, code),
  unique (store_id, id)
);

create table public.sales (
  id uuid primary key,
  store_id uuid not null references public.stores,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  payment text not null check (payment in ('cash', 'pix', 'credit', 'debit')),
  total_cents bigint not null default 0 check (total_cents >= 0),
  cancelled_at timestamptz,
  cancelled_by uuid,
  unique (store_id, id)
);
create index sales_store_date on public.sales (store_id, created_at desc, id desc);

create table public.sale_items (
  store_id uuid not null,
  sale_id uuid not null,
  product_id uuid not null,
  product_name text not null,
  product_code text not null,
  quantity integer not null check (quantity > 0),
  price_cents integer not null check (price_cents > 0),
  primary key (sale_id, product_id),
  foreign key (store_id, sale_id) references public.sales (store_id, id),
  foreign key (store_id, product_id) references public.products (store_id, id)
);

create schema venda_private;
create function venda_private.store_role(p_store uuid) returns text
language sql stable security definer set search_path = '' as $$
  select role from public.members where store_id = p_store and user_id = auth.uid();
$$;
revoke all on schema venda_private from public;
grant usage on schema venda_private to authenticated;
revoke all on function venda_private.store_role(uuid) from public;
grant execute on function venda_private.store_role(uuid) to authenticated;

alter table public.stores enable row level security;
alter table public.members enable row level security;
alter table public.products enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
revoke all on public.stores, public.members, public.products, public.sales, public.sale_items from anon, authenticated;
grant select on public.stores, public.members, public.products, public.sales, public.sale_items to authenticated;
grant insert (store_id, name, code, price_cents, stock, min_stock)
  on public.products to authenticated;

create policy read_stores on public.stores for select to authenticated using (venda_private.store_role(id) is not null);
create policy read_own_memberships on public.members for select to authenticated using (user_id = (select auth.uid()));
create policy read_products on public.products for select to authenticated using (venda_private.store_role(store_id) is not null);
create policy create_products on public.products for insert to authenticated with check (venda_private.store_role(store_id) = 'admin');
create policy read_sales on public.sales for select to authenticated using (venda_private.store_role(store_id) is not null);
create policy read_sale_items on public.sale_items for select to authenticated using (venda_private.store_role(store_id) is not null);

create function public.create_store(p_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_store uuid;
begin
  if auth.uid() is null then raise exception 'Sessão inválida'; end if;
  insert into public.stores (name) values (trim(p_name)) returning id into v_store;
  insert into public.members values (v_store, auth.uid(), 'admin');
  return v_store;
end;
$$;

create function public.add_operator(p_store uuid, p_email text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_user uuid;
begin
  if venda_private.store_role(p_store) is distinct from 'admin' then raise exception 'Acesso restrito à administração'; end if;
  select id into v_user from auth.users where lower(email) = lower(trim(p_email)) and email_confirmed_at is not null;
  if v_user is null then raise exception 'A conta precisa estar cadastrada e com o e-mail confirmado'; end if;
  insert into public.members values (p_store, v_user, 'operator') on conflict do nothing;
end;
$$;

create function public.update_product(p_store uuid, p_id uuid, p_name text, p_code text,
  p_price integer, p_stock integer, p_min integer, p_expected_stock integer) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if venda_private.store_role(p_store) is distinct from 'admin' then raise exception 'Acesso restrito à administração'; end if;
  update public.products set name = p_name, code = p_code, price_cents = p_price,
    min_stock = p_min, stock = case when p_stock = p_expected_stock then stock else p_stock end
  where store_id = p_store and id = p_id and (p_stock = p_expected_stock or stock = p_expected_stock);
  if not found then raise exception 'O estoque mudou. Atualize os produtos e tente novamente'; end if;
end;
$$;

create function public.record_sale(p_store uuid, p_id uuid, p_payment text, p_items jsonb, p_expected_total bigint) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_line record;
  v_product public.products%rowtype;
  v_total bigint := 0;
begin
  if venda_private.store_role(p_store) is null then raise exception 'Acesso negado'; end if;
  if jsonb_typeof(p_items) is distinct from 'object' or p_items = '{}'::jsonb then raise exception 'Adicione produtos à venda'; end if;
  insert into public.sales (id, store_id, created_by, payment) values (p_id, p_store, auth.uid(), p_payment)
    on conflict (id) do nothing;
  if not found then
    if exists (select 1 from public.sales where id = p_id and store_id = p_store and created_by = auth.uid()) then return p_id; end if;
    raise exception 'Identificador de venda indisponível';
  end if;
  for v_line in select key::uuid as id, value::integer as qty from jsonb_each_text(p_items) order by key::uuid loop
    select * into v_product from public.products where store_id = p_store and id = v_line.id for update;
    if not found then raise exception 'Produto indisponível'; end if;
    if v_line.qty is null or v_line.qty <= 0 or v_line.qty > v_product.stock then
      raise exception 'Quantidade indisponível para %', v_product.name;
    end if;
    insert into public.sale_items values (p_store, p_id, v_product.id, v_product.name, v_product.code, v_line.qty, v_product.price_cents);
    update public.products set stock = stock - v_line.qty where id = v_product.id;
    v_total := v_total + v_line.qty::bigint * v_product.price_cents;
  end loop;
  if v_total is distinct from p_expected_total then
    raise exception 'O total da venda mudou. Confira os preços e confirme novamente';
  end if;
  update public.sales set total_cents = v_total where id = p_id;
  return p_id;
end;
$$;

create function public.cancel_sale(p_store uuid, p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_item record;
begin
  if venda_private.store_role(p_store) is distinct from 'admin' then raise exception 'Apenas administradores podem cancelar vendas'; end if;
  update public.sales set cancelled_at = now(), cancelled_by = auth.uid()
    where store_id = p_store and id = p_id and cancelled_at is null;
  if not found then return; end if;
  for v_item in select product_id, quantity from public.sale_items where sale_id = p_id order by product_id loop
    update public.products set stock = stock + v_item.quantity where id = v_item.product_id and store_id = p_store;
  end loop;
end;
$$;

create function public.revenue(p_store uuid, p_year integer, p_month integer, p_day integer default null)
returns table (total_cents bigint, sale_count bigint)
language sql stable security invoker set search_path = '' as $$
  with period as (select make_date(p_year, p_month, coalesce(p_day, 1))::timestamp as start_at)
  select coalesce(sum(s.total_cents), 0)::bigint, count(*)
  from public.sales s cross join period p
  where s.store_id = p_store and s.cancelled_at is null
    and s.created_at >= p.start_at at time zone 'America/Sao_Paulo'
    and s.created_at < (p.start_at + case when p_day is null then interval '1 month' else interval '1 day' end) at time zone 'America/Sao_Paulo';
$$;

revoke all on function public.create_store(text), public.add_operator(uuid,text), public.update_product(uuid,uuid,text,text,integer,integer,integer,integer), public.record_sale(uuid,uuid,text,jsonb,bigint), public.cancel_sale(uuid,uuid), public.revenue(uuid,integer,integer,integer) from public, anon, authenticated;
grant execute on function public.create_store(text), public.add_operator(uuid,text), public.update_product(uuid,uuid,text,text,integer,integer,integer,integer), public.record_sale(uuid,uuid,text,jsonb,bigint), public.cancel_sale(uuid,uuid), public.revenue(uuid,integer,integer,integer) to authenticated;

begin;

insert into auth.users (id, email, email_confirmed_at) values
  ('10000000-0000-0000-0000-000000000001', 'vf-admin@example.invalid', now()),
  ('10000000-0000-0000-0000-000000000002', 'vf-operator@example.invalid', now()),
  ('10000000-0000-0000-0000-000000000003', 'vf-outsider@example.invalid', now());

set local role authenticated;
do $$
<<sales_test>>
declare
  admin_id constant uuid := '10000000-0000-0000-0000-000000000001';
  operator_id constant uuid := '10000000-0000-0000-0000-000000000002';
  outsider_id constant uuid := '10000000-0000-0000-0000-000000000003';
  sale_id constant uuid := '20000000-0000-0000-0000-000000000001';
  rejected_id constant uuid := '20000000-0000-0000-0000-000000000002';
  v_store uuid;
  v_product uuid;
  v_items jsonb;
  v_today date := (now() at time zone 'America/Sao_Paulo')::date;
  v_report record;
begin
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  v_store := public.create_store('Loja de teste');
  perform public.add_operator(v_store, 'vf-operator@example.invalid');
  insert into public.products (store_id, name, code, price_cents, stock, min_stock)
    values (v_store, 'Café', 'CAFE', 1500, 5, 2)
    returning id into v_product;
  v_items := jsonb_build_object(v_product, 3);

  perform set_config('request.jwt.claim.sub', operator_id::text, true);
  begin
    perform public.record_sale(v_store, rejected_id, 'pix', v_items, 4499);
    raise exception 'Preço divergente foi aceito';
  exception when raise_exception then
    if sqlerrm <> 'O total da venda mudou. Confira os preços e confirme novamente' then raise; end if;
  end;
  if exists (select 1 from public.sales where id = rejected_id) or
      (select stock from public.products where id = v_product) is distinct from 5 then
    raise exception 'Venda rejeitada alterou o estoque ou ficou no histórico';
  end if;
  perform public.record_sale(v_store, sale_id, 'pix', v_items, 4500);
  perform public.record_sale(v_store, sale_id, 'pix', v_items, 4500);
  if (select stock from public.products where id = v_product) is distinct from 2 then
    raise exception 'A baixa da venda com reenvio foi incorreta';
  end if;

  select * into v_report from public.revenue(v_store, extract(year from v_today)::int,
    extract(month from v_today)::int, extract(day from v_today)::int);
  if v_report.sale_count <> 1 or v_report.total_cents <> 4500 then
    raise exception 'Faturamento diário incorreto';
  end if;

  begin
    perform public.cancel_sale(v_store, sale_id);
    raise exception 'Operador conseguiu cancelar venda';
  exception when raise_exception then
    if sqlerrm <> 'Apenas administradores podem cancelar vendas' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub', outsider_id::text, true);
  if exists (select 1 from public.products where id = v_product) or
      exists (select 1 from public.sales where id = sale_id) or
      exists (select 1 from public.sale_items where sale_items.sale_id = sales_test.sale_id) then
    raise exception 'A conta externa visualizou dados da loja';
  end if;

  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform public.cancel_sale(v_store, sale_id);
  perform public.cancel_sale(v_store, sale_id);
  if (select stock from public.products where id = v_product) is distinct from 5 then
    raise exception 'A reposição da venda cancelada foi incorreta';
  end if;

  select * into v_report from public.revenue(v_store, extract(year from v_today)::int,
    extract(month from v_today)::int);
  if v_report.sale_count <> 0 or v_report.total_cents <> 0 then
    raise exception 'Venda cancelada entrou no faturamento mensal';
  end if;
end;
$$;

rollback;

import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef RowData = Map<String, dynamic>;

final db = Supabase.instance.client;
final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
String money(num cents) => currency.format(cents / 100);
DateTime brazilToday() {
  final now = DateTime.now().toUtc().subtract(const Duration(hours: 3));
  return DateTime(now.year, now.month, now.day);
}

String dateLabel(Object? value) => DateFormat('dd/MM/yyyy • HH:mm').format(
  DateTime.parse(value.toString()).toUtc().subtract(const Duration(hours: 3)),
);

const payments = {
  'pix': 'Pix',
  'cash': 'Dinheiro',
  'credit': 'Cartão de crédito',
  'debit': 'Cartão de débito',
};

String errorLabel(Object error) {
  if (error is PostgrestException) {
    if (error.code == '23505')
      return 'Já existe um produto com esse código nesta loja.';
    if (error.code == 'P0001') return error.message;
  }
  if (error is AuthException) {
    return switch (error.code) {
      'invalid_credentials' => 'E-mail ou senha inválidos.',
      'email_not_confirmed' => 'Confirme seu e-mail para entrar.',
      'email_address_not_authorized' =>
        'O envio de e-mail para esse endereço ainda não está habilitado no projeto.',
      'weak_password' => 'Escolha uma senha mais forte.',
      'over_email_send_rate_limit' =>
        'Aguarde antes de solicitar outro e-mail.',
      _ => 'Não foi possível autenticar. Confira seus dados e tente novamente.',
    };
  }
  return 'Não foi possível concluir agora. Tente novamente.';
}

class Product {
  Product(RowData row)
    : id = row['id'] as String,
      name = row['name'] as String,
      code = row['code'] as String,
      price = row['price_cents'] as int,
      stock = row['stock'] as int,
      minimum = row['min_stock'] as int;

  final String id, name, code;
  final int price, stock, minimum;
  bool get low => stock <= minimum;
}

class Store {
  Store(RowData row)
    : id = row['store_id'] as String,
      name = (row['stores'] as RowData)['name'] as String,
      isAdmin = row['role'] == 'admin';

  final String id, name;
  final bool isAdmin;
}

class Inventory {
  Inventory(this.store);
  final Store store;

  Future<List<Product>> products() async {
    final products = <Product>[];
    const pageSize = 500;
    for (var start = 0; ; start += pageSize) {
      final rows = await db
          .from('products')
          .select()
          .eq('store_id', store.id)
          .order('name')
          .order('id')
          .range(start, start + pageSize - 1);
      products.addAll(rows.map(Product.new));
      if (rows.length < pageSize) return products;
    }
  }

  Future<void> save(
    Product? existing,
    String name,
    String code,
    int price,
    int stock,
    int minimum,
  ) async {
    if (existing == null) {
      await db.from('products').insert({
        'store_id': store.id,
        'name': name,
        'code': code,
        'price_cents': price,
        'stock': stock,
        'min_stock': minimum,
      });
      return;
    }
    await db.rpc(
      'update_product',
      params: {
        'p_store': store.id,
        'p_id': existing.id,
        'p_name': name,
        'p_code': code,
        'p_price': price,
        'p_stock': stock,
        'p_min': minimum,
        'p_expected_stock': existing.stock,
      },
    );
  }

  Future<void> sell(
    String id,
    String payment,
    Map<String, int> items,
    int total,
  ) async {
    await db.rpc(
      'record_sale',
      params: {
        'p_store': store.id,
        'p_id': id,
        'p_payment': payment,
        'p_items': items,
        'p_expected_total': total,
      },
    );
  }

  Future<List<RowData>> sales(int offset, int limit) => db
      .from('sales')
      .select()
      .eq('store_id', store.id)
      .order('created_at')
      .order('id')
      .range(offset, offset + limit - 1);

  Future<List<RowData>> items(String sale) => db
      .from('sale_items')
      .select()
      .eq('store_id', store.id)
      .eq('sale_id', sale)
      .order('product_name');

  Future<void> cancel(String sale) async {
    await db.rpc('cancel_sale', params: {'p_store': store.id, 'p_id': sale});
  }

  Future<RowData> revenue(DateTime date, {required bool monthly}) async {
    final rows = await db.rpc<List<dynamic>>(
      'revenue',
      params: {
        'p_store': store.id,
        'p_year': date.year,
        'p_month': date.month,
        'p_day': monthly ? null : date.day,
      },
    );
    return rows.single as RowData;
  }
}

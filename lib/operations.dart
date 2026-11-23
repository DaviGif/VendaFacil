import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:uuid/uuid.dart';
import 'data.dart';
import 'workspace.dart';

class Catalog extends StatefulWidget {
  const Catalog({
    super.key,
    required this.inventory,
    required this.products,
    required this.onChange,
  });
  final Inventory inventory;
  final List<Product> products;
  final VoidCallback onChange;

  @override
  State<Catalog> createState() => _CatalogState();
}

class _CatalogState extends State<Catalog> {
  String query = '';
  bool lowOnly = false;

  Future<void> edit([Product? product]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProductEditor(widget.inventory, product),
    );
    if (saved == true && mounted) {
      widget.onChange();
      notify(context, 'Produto salvo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.products.where(
      (p) =>
          (!lowOnly || p.low) &&
          '${p.name} ${p.code}'.toLowerCase().contains(query),
    );
    return PageBody(
      'Produtos',
      'Consulte o catálogo e acompanhe a disponibilidade.',
      [
        TextFormField(
          initialValue: query,
          decoration: const InputDecoration(
            labelText: 'Buscar por nome ou código',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) =>
              setState(() => query = value.trim().toLowerCase()),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilterChip(
            label: const Text('Estoque no limite'),
            selected: lowOnly,
            onSelected: (value) => setState(() => lowOnly = value),
          ),
        ),
        const SizedBox(height: 12),
        if (products.isEmpty)
          const Card(
            child: ListTile(title: Text('Nenhum produto encontrado.')),
          ),
        for (final p in products)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                leading: Icon(
                  p.low ? Icons.warning_amber : Icons.inventory_2_outlined,
                ),
                title: Text(p.name),
                subtitle: Text(
                  '${p.code} · ${money(p.price)}\nEstoque: ${p.stock} · Mínimo: ${p.minimum}',
                ),
                isThreeLine: true,
                trailing: widget.inventory.store.isAdmin
                    ? IconButton(
                        tooltip: 'Editar ${p.name}',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => edit(p),
                      )
                    : null,
              ),
            ),
          ),
      ],
      action: widget.inventory.store.isAdmin
          ? FilledButton.icon(
              onPressed: () => edit(),
              icon: const Icon(Icons.add),
              label: const Text('Novo produto'),
            )
          : null,
    );
  }
}

class _ProductEditor extends StatefulWidget {
  const _ProductEditor(this.inventory, this.product);
  final Inventory inventory;
  final Product? product;

  @override
  State<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<_ProductEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.product?.name);
  late final code = TextEditingController(text: widget.product?.code);
  late final price = TextEditingController(
    text: widget.product == null
        ? ''
        : (widget.product!.price / 100).toStringAsFixed(2).replaceAll('.', ','),
  );
  late final stock = TextEditingController(
    text: '${widget.product?.stock ?? 0}',
  );
  late final minimum = TextEditingController(
    text: '${widget.product?.minimum ?? 0}',
  );
  bool busy = false;
  String? error;

  @override
  void dispose() {
    for (final controller in [name, code, price, stock, minimum]) {
      controller.dispose();
    }
    super.dispose();
  }

  int? cents(String raw) {
    final value = raw.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) return null;
    final parts = value.split('.');
    final whole = int.tryParse(parts.first);
    if (whole == null || whole > 21474836) return null;
    return whole * 100 +
        (parts.length == 2 ? int.parse(parts.last.padRight(2, '0')) : 0);
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.inventory.save(
        widget.product,
        name.text.trim(),
        code.text.trim(),
        cents(price.text)!,
        int.parse(stock.text.trim()),
        int.parse(minimum.text.trim()),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (exception) {
      if (mounted)
        setState(() {
          busy = false;
          error = errorLabel(exception);
        });
    }
  }

  Widget field(
    TextEditingController controller,
    String label,
    String? Function(String) validate, {
    int? max,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      maxLength: max,
      enabled: !busy,
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label, counterText: ''),
      validator: (value) => validate(value?.trim() ?? ''),
    ),
  );

  String? requiredText(String value) =>
      value.isEmpty ? 'Campo obrigatório' : null;
  String? quantity(String value) {
    final parsed = int.tryParse(value);
    return parsed == null || parsed < 0 || parsed > 2147483647
        ? 'Informe uma quantidade inteira válida'
        : null;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      scrollable: true,
      title: Text(widget.product == null ? 'Novo produto' : 'Editar produto'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              field(name, 'Nome', requiredText, max: 120),
              field(code, 'Código', requiredText, max: 40),
              field(
                price,
                'Preço em reais',
                (value) {
                  final parsed = cents(value);
                  return parsed == null || parsed <= 0 || parsed > 2147483647
                      ? 'Informe um preço válido, como 12,50'
                      : null;
                },
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
              field(
                stock,
                'Quantidade em estoque',
                quantity,
                keyboard: TextInputType.number,
              ),
              field(
                minimum,
                'Estoque mínimo',
                quantity,
                keyboard: TextInputType.number,
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(busy ? 'Salvando…' : 'Salvar'),
        ),
      ],
    ),
  );
}

class Checkout extends StatefulWidget {
  const Checkout({
    super.key,
    required this.inventory,
    required this.products,
    required this.onSale,
  });
  final Inventory inventory;
  final List<Product> products;
  final VoidCallback onSale;

  @override
  State<Checkout> createState() => _CheckoutState();
}

class _CheckoutState extends State<Checkout> {
  final cart = <String, int>{};
  String payment = 'pix', query = '';
  String? requestId, message;
  bool busy = false, retryOnly = false;
  int? submittedTotal;

  void change(Product product, int amount) {
    final quantity = (cart[product.id] ?? 0) + amount;
    setState(() {
      if (quantity <= 0) {
        cart.remove(product.id);
      } else {
        cart[product.id] = quantity;
      }
      message = null;
    });
  }

  Future<void> submit(int total) async {
    if (busy) return;
    requestId ??= const Uuid().v4();
    submittedTotal ??= total;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await widget.inventory.sell(requestId!, payment, cart, submittedTotal!);
      widget.onSale();
      if (!mounted) return;
      setState(() {
        cart.clear();
        requestId = null;
        submittedTotal = null;
        busy = false;
        retryOnly = false;
      });
      notify(context, 'Venda registrada e estoque atualizado.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        busy = false;
        retryOnly = error is! PostgrestException || error.code != 'P0001';
        if (!retryOnly) {
          requestId = null;
          submittedTotal = null;
        }
        message = retryOnly
            ? 'A confirmação ficou pendente. Tente confirmar novamente ou confira o histórico antes de iniciar outra venda.'
            : errorLabel(error);
      });
      if (!retryOnly) widget.onSale();
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = busy || retryOnly;
    final products = widget.products;
    final cartLines = products.where((p) => cart.containsKey(p.id)).toList();
    final total = cartLines.fold<int>(
      0,
      (sum, p) => sum + p.price * cart[p.id]!,
    );
    final valid =
        cart.isNotEmpty &&
        cartLines.length == cart.length &&
        cartLines.every((p) => cart[p.id]! <= p.stock);
    final matches = products.where(
      (p) => '${p.name} ${p.code}'.toLowerCase().contains(query),
    );
    return PageBody(
      'Nova venda',
      'Selecione os produtos e confirme a operação.',
      [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Itens da venda',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (cartLines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('O carrinho está vazio.'),
                  ),
                for (final product in cartLines)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(product.name),
                    subtitle: Text(
                      '${cart[product.id]} × ${money(product.price)}',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Retirar unidade',
                          onPressed: disabled
                              ? null
                              : () => change(product, -1),
                          icon: const Icon(Icons.remove),
                        ),
                        IconButton(
                          tooltip: 'Adicionar unidade',
                          onPressed:
                              disabled || cart[product.id]! >= product.stock
                              ? null
                              : () => change(product, 1),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: payment,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Forma de pagamento',
                  ),
                  items: payments.entries
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.key,
                          child: Text(item.value),
                        ),
                      )
                      .toList(),
                  onChanged: disabled
                      ? null
                      : (value) => setState(() => payment = value!),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Registro demonstrativo da forma de pagamento.'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Total  ${money(submittedTotal ?? total)}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (!retryOnly && cart.isNotEmpty && !valid)
                  const Text(
                    'Ajuste as quantidades conforme o estoque disponível.',
                  ),
                if (message != null)
                  Text(
                    message!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: busy || (!valid && !retryOnly)
                      ? null
                      : () => submit(total),
                  icon: const Icon(Icons.check),
                  label: Text(busy ? 'Confirmando…' : 'Confirmar venda'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        TextFormField(
          initialValue: query,
          decoration: const InputDecoration(
            labelText: 'Buscar produto para adicionar',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) =>
              setState(() => query = value.trim().toLowerCase()),
        ),
        const SizedBox(height: 12),
        if (matches.isEmpty)
          const Card(
            child: ListTile(title: Text('Nenhum produto encontrado.')),
          ),
        for (final product in matches)
          Card(
            child: ListTile(
              key: ValueKey(product.id),
              title: Text(product.name),
              subtitle: Text(
                '${product.code} · ${money(product.price)} · Estoque: ${product.stock}',
              ),
              trailing: IconButton(
                tooltip: 'Adicionar ${product.name}',
                onPressed: disabled || (cart[product.id] ?? 0) >= product.stock
                    ? null
                    : () => change(product, 1),
                icon: const Icon(Icons.add_shopping_cart),
              ),
            ),
          ),
      ],
    );
  }
}

class History extends StatefulWidget {
  const History({super.key, required this.inventory, required this.onChange});
  final Inventory inventory;
  final VoidCallback onChange;

  @override
  State<History> createState() => _HistoryState();
}

class _HistoryState extends State<History> {
  static const limit = 20;
  int page = 0;
  late Future<List<RowData>> sales = load();

  Future<List<RowData>> load() =>
      widget.inventory.sales(page * limit, limit + 1);

  void turn(int target) => setState(() {
    page = target;
    sales = load();
  });

  Future<void> details(RowData sale) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SaleDetails(widget.inventory, sale),
    );
    if (mounted && changed == true) {
      widget.onChange();
      notify(context, 'Venda cancelada e estoque recomposto.');
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => PageBody('Histórico', 'Consulte as vendas e os itens de cada operação.', [
    FutureBuilder<List<RowData>>(
      future: sales,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return Retry(error: snapshot.error!, onRetry: () => turn(page));
        final rows = snapshot.data!;
        return Column(
          children: [
            if (rows.isEmpty)
              const Card(
                child: ListTile(title: Text('Nenhuma venda nesta página.')),
              ),
            for (final sale in rows.take(limit))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: Icon(
                      sale['cancelled_at'] == null
                          ? Icons.receipt_long_outlined
                          : Icons.cancel_outlined,
                    ),
                    title: Text(money(sale['total_cents'] as num)),
                    subtitle: Text(
                      '${dateLabel(sale['created_at'])}\n${payments[sale['payment']]} · ${sale['cancelled_at'] == null ? 'Confirmada' : 'Cancelada'}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => details(sale),
                  ),
                ),
              ),
            if (page > 0 || rows.length > limit)
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: page == 0 ? null : () => turn(page - 1),
                    child: const Text('Anterior'),
                  ),
                  Text('Página ${page + 1}'),
                  TextButton(
                    onPressed: rows.length <= limit
                        ? null
                        : () => turn(page + 1),
                    child: const Text('Próxima'),
                  ),
                ],
              ),
          ],
        );
      },
    ),
  ]);
}

class _SaleDetails extends StatefulWidget {
  const _SaleDetails(this.inventory, this.sale);
  final Inventory inventory;
  final RowData sale;

  @override
  State<_SaleDetails> createState() => _SaleDetailsState();
}

class _SaleDetailsState extends State<_SaleDetails> {
  String get id => widget.sale['id'] as String;
  late Future<List<RowData>> items = widget.inventory.items(id);
  bool confirming = false, busy = false;
  String? error;

  Future<void> cancel() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.inventory.cancel(id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (exception) {
      if (mounted)
        setState(() {
          busy = false;
          error = errorLabel(exception);
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      scrollable: true,
      title: Text(confirming ? 'Cancelar esta venda?' : 'Detalhes da venda'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dateLabel(widget.sale['created_at'])),
            Text(
              '${payments[widget.sale['payment']]} · ${money(widget.sale['total_cents'] as num)}',
            ),
            if (widget.sale['cancelled_at'] != null)
              Text('Cancelada em ${dateLabel(widget.sale['cancelled_at'])}'),
            if (confirming)
              const Text('As quantidades vendidas retornarão ao estoque.'),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            FutureBuilder<List<RowData>>(
              future: items,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done)
                  return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError)
                  return Retry(
                    error: snapshot.error!,
                    onRetry: () =>
                        setState(() => items = widget.inventory.items(id)),
                  );
                return Column(
                  children: [
                    for (final item in snapshot.data!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item['product_name'] as String),
                        subtitle: Text(
                          '${item['product_code']} · ${item['quantity']} × ${money(item['price_cents'] as num)}',
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
        if (widget.inventory.store.isAdmin &&
            widget.sale['cancelled_at'] == null)
          FilledButton(
            onPressed: busy
                ? null
                : confirming
                ? cancel
                : () => setState(() => confirming = true),
            child: Text(
              busy
                  ? 'Cancelando…'
                  : confirming
                  ? 'Confirmar cancelamento'
                  : 'Cancelar venda',
            ),
          ),
      ],
    ),
  );
}

class Reports extends StatefulWidget {
  const Reports({super.key, required this.inventory});
  final Inventory inventory;

  @override
  State<Reports> createState() => _ReportsState();
}

class _ReportsState extends State<Reports> {
  DateTime date = brazilToday();
  bool monthly = false;
  late Future<RowData> report = load();

  Future<RowData> load() => widget.inventory.revenue(date, monthly: monthly);

  Future<void> selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: brazilToday(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      date = picked;
      report = load();
    });
  }

  @override
  Widget build(BuildContext context) => PageBody(
    'Relatórios',
    'Faturamento de vendas confirmadas no horário de Brasília.',
    [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          ChoiceChip(
            label: const Text('Diário'),
            selected: !monthly,
            onSelected: (_) => setState(() {
              monthly = false;
              report = load();
            }),
          ),
          ChoiceChip(
            label: const Text('Mensal'),
            selected: monthly,
            onSelected: (_) => setState(() {
              monthly = true;
              report = load();
            }),
          ),
          OutlinedButton.icon(
            onPressed: selectDate,
            icon: const Icon(Icons.calendar_today),
            label: Text(
              DateFormat(monthly ? 'MM/yyyy' : 'dd/MM/yyyy').format(date),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      FutureBuilder<RowData>(
        future: report,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
            return Retry(
              error: snapshot.error!,
              onRetry: () => setState(() => report = load()),
            );
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              Metric(
                'Faturamento',
                money(snapshot.data!['total_cents'] as num),
                Icons.payments_outlined,
              ),
              Metric(
                'Vendas confirmadas',
                '${snapshot.data!['sale_count']}',
                Icons.receipt_long_outlined,
              ),
            ],
          );
        },
      ),
    ],
  );
}

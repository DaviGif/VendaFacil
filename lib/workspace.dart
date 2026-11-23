import 'package:material_ui/material_ui.dart';
import 'data.dart';
import 'main.dart' show green, signOut, title;
import 'operations.dart';

const sections = [
  (Icons.space_dashboard_outlined, 'Visão geral'),
  (Icons.shopping_cart_outlined, 'Nova venda'),
  (Icons.inventory_2_outlined, 'Produtos'),
  (Icons.receipt_long_outlined, 'Histórico'),
  (Icons.bar_chart_outlined, 'Relatórios'),
];

class Workspace extends StatefulWidget {
  const Workspace({super.key, required this.store, required this.onSwitch});
  final Store store;
  final VoidCallback onSwitch;

  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  late final inventory = Inventory(widget.store);
  Future<List<Product>>? cachedProducts;
  Future<List<Product>> get products => cachedProducts ??= inventory.products();
  int section = 0;
  int revision = 0;

  void refresh() {
    if (!mounted) return;
    setState(() {
      cachedProducts = null;
      revision++;
    });
  }

  Future<void> addOperator() async {
    final email = await askText(
      context,
      'Adicionar operador',
      'E-mail da conta cadastrada',
      254,
    );
    if (email == null || !mounted) return;
    try {
      await db.rpc(
        'add_operator',
        params: {'p_store': widget.store.id, 'p_email': email},
      );
      if (mounted) notify(context, 'Acesso de operador concedido.');
    } catch (error) {
      if (mounted) notify(context, errorLabel(error));
    }
  }

  Widget page() => switch (section) {
    1 => ProductData(
      future: products,
      retry: refresh,
      builder: (list) =>
          Checkout(inventory: inventory, products: list, onSale: refresh),
    ),
    2 => ProductData(
      future: products,
      retry: refresh,
      builder: (list) =>
          Catalog(inventory: inventory, products: list, onChange: refresh),
    ),
    3 => History(
      key: ValueKey(revision),
      inventory: inventory,
      onChange: refresh,
    ),
    4 => Reports(key: ValueKey(revision), inventory: inventory),
    _ => Dashboard(
      key: ValueKey(revision),
      inventory: inventory,
      products: products,
      retry: refresh,
      onSection: (value) => setState(() => section = value),
    ),
  };

  Widget menu(bool drawer) => ColoredBox(
    color: const Color(0xff152b28),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ListTile(
            leading: Icon(Icons.storefront, color: Color(0xff70e0b5)),
            title: Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 24),
          for (var index = 0; index < sections.length; index++)
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textColor: const Color(0xffd5e4dd),
              iconColor: const Color(0xffd5e4dd),
              leading: Icon(sections[index].$1),
              title: Text(sections[index].$2),
              selected: section == index,
              selectedColor: const Color(0xffa7efce),
              selectedTileColor: const Color(0xff24463e),
              onTap: () {
                if (drawer) Navigator.of(context).pop();
                setState(() => section = index);
              },
            ),
          const SizedBox(height: 24),
          ListTile(
            title: Text(
              widget.store.name,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              widget.store.isAdmin ? 'Administração' : 'Operação',
              style: const TextStyle(color: Color(0xffb0c7be)),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 960;
      return Scaffold(
        drawer: wide ? null : Drawer(child: menu(true)),
        appBar: AppBar(
          backgroundColor: Colors.white,
          title: Text(
            wide ? widget.store.name : title,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Atualizar',
              onPressed: refresh,
              icon: const Icon(Icons.refresh),
            ),
            PopupMenuButton<String>(
              tooltip: 'Opções da loja',
              onSelected: (action) {
                if (action == 'operator') addOperator();
                if (action == 'switch') widget.onSwitch();
                if (action == 'exit') signOut(context);
              },
              itemBuilder: (_) => [
                if (widget.store.isAdmin)
                  const PopupMenuItem(
                    value: 'operator',
                    child: Text('Adicionar operador'),
                  ),
                const PopupMenuItem(
                  value: 'switch',
                  child: Text('Trocar de loja'),
                ),
                const PopupMenuItem(value: 'exit', child: Text('Sair')),
              ],
            ),
          ],
        ),
        body: Row(
          children: [
            if (wide) SizedBox(width: 232, child: menu(false)),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: page(),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class ProductData extends StatelessWidget {
  const ProductData({
    super.key,
    required this.future,
    required this.retry,
    required this.builder,
  });
  final Future<List<Product>> future;
  final VoidCallback retry;
  final Widget Function(List<Product>) builder;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Product>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done &&
          !snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Retry(error: snapshot.error!, onRetry: retry),
        );
      }
      return builder(snapshot.data!);
    },
  );
}

class PageBody extends StatelessWidget {
  const PageBody(
    this.heading,
    this.description,
    this.children, {
    super.key,
    this.action,
  });
  final String heading, description;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 20,
        runSpacing: 14,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                heading,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(color: Color(0xff50635b)),
              ),
            ],
          ),
          if (action != null) action!,
        ],
      ),
      const SizedBox(height: 24),
      ...children,
    ],
  );
}

class Metric extends StatelessWidget {
  const Metric(this.label, this.value, this.icon, {super.key});
  final String label, value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: green),
          const SizedBox(height: 12),
          Text(label),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class Dashboard extends StatelessWidget {
  Dashboard({
    super.key,
    required this.inventory,
    required this.products,
    required this.retry,
    required this.onSection,
  });
  final Inventory inventory;
  final Future<List<Product>> products;
  final VoidCallback retry;
  final ValueChanged<int> onSection;
  late final total = inventory.revenue(brazilToday(), monthly: false);

  @override
  Widget build(BuildContext context) => ProductData(
    future: products,
    retry: retry,
    builder: (list) {
      final low = list.where((product) => product.low).toList();
      return PageBody(
        'Visão geral',
        'Acompanhe as vendas e os alertas da sua loja.',
        [
          FutureBuilder<RowData>(
            future: total,
            builder: (context, snapshot) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                Metric(
                  'Faturamento de hoje',
                  snapshot.hasData
                      ? money(snapshot.data!['total_cents'] as num)
                      : snapshot.hasError
                      ? 'Indisponível'
                      : '…',
                  Icons.payments_outlined,
                ),
                Metric(
                  'Produtos cadastrados',
                  '${list.length}',
                  Icons.inventory_2_outlined,
                ),
                Metric(
                  'Estoque no limite',
                  '${low.length}',
                  Icons.warning_amber,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  title: const Text('Alertas de estoque'),
                  trailing: TextButton(
                    onPressed: () => onSection(2),
                    child: const Text('Ver produtos'),
                  ),
                ),
                if (low.isEmpty)
                  const ListTile(
                    title: Text('Nenhum produto atingiu o estoque mínimo.'),
                  ),
                for (final product in low.take(10))
                  ListTile(
                    leading: const Icon(
                      Icons.warning_amber,
                      color: Color(0xff8a4e00),
                    ),
                    title: Text(product.name),
                    subtitle: Text(
                      '${product.stock} em estoque · mínimo de ${product.minimum}',
                    ),
                  ),
              ],
            ),
          ),
        ],
        action: FilledButton.icon(
          onPressed: () => onSection(1),
          icon: const Icon(Icons.add),
          label: const Text('Nova venda'),
        ),
      );
    },
  );
}

class Retry extends StatelessWidget {
  const Retry({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(errorLabel(error)),
        TextButton(onPressed: onRetry, child: const Text('Tentar novamente')),
      ],
    ),
  );
}

void notify(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));

Future<String?> askText(
  BuildContext context,
  String heading,
  String label,
  int maxLength,
) => showDialog<String>(
  context: context,
  builder: (_) => _TextDialog(heading, label, maxLength),
);

class _TextDialog extends StatefulWidget {
  const _TextDialog(this.heading, this.label, this.maxLength);
  final String heading, label;
  final int maxLength;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  String value = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.heading),
    content: TextField(
      autofocus: true,
      maxLength: widget.maxLength,
      decoration: InputDecoration(labelText: widget.label),
      onChanged: (text) => setState(() => value = text.trim()),
      onSubmitted: (_) {
        if (value.isNotEmpty) Navigator.of(context).pop(value);
      },
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Voltar'),
      ),
      FilledButton(
        onPressed: value.isEmpty
            ? null
            : () => Navigator.of(context).pop(value),
        child: const Text('Confirmar'),
      ),
    ],
  );
}

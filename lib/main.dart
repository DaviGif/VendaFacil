import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'data.dart';
import 'workspace.dart';

const title = 'VendaFácil';
const green = Color(0xff007858);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_KEY');
  final configured = url.isNotEmpty && key.isNotEmpty;
  if (configured) await Supabase.initialize(url: url, publishableKey: key);
  runApp(
    MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: green,
        ).copyWith(primary: green),
        scaffoldBackgroundColor: const Color(0xfff3f6f4),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      home: configured
          ? const SessionGate()
          : const Scaffold(
              body: Center(
                child: Text(
                  'Conecte o projeto Supabase para iniciar o VendaFácil.',
                ),
              ),
            ),
    ),
  );
}

class SessionGate extends StatelessWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: db.auth.onAuthStateChange,
    builder: (context, snapshot) {
      final user = db.auth.currentUser;
      return user == null ? const Login() : StoreGate(key: ValueKey(user.id));
    },
  );
}

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool signup = false, busy = false, hidden = true;
  String? message;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (signup) {
        final response = await db.auth.signUp(
          email: email.text.trim(),
          password: password.text,
        );
        if (mounted && response.session == null) {
          setState(() {
            signup = false;
            message = 'Confira seu e-mail para confirmar o cadastro.';
          });
        }
      } else {
        await db.auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } catch (error) {
      if (mounted) setState(() => message = errorLabel(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Form(
                key: form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: CircleAvatar(
                          backgroundColor: green,
                          foregroundColor: Colors.white,
                          child: Icon(Icons.storefront),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const Text('Gestão de vendas e estoque'),
                      const SizedBox(height: 28),
                      Text(
                        signup ? 'Criar uma conta' : 'Acessar minha conta',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'E-mail'),
                        validator: (value) =>
                            value == null || !value.contains('@')
                            ? 'Informe seu e-mail'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: password,
                        obscureText: hidden,
                        autofillHints: [
                          signup
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        decoration: InputDecoration(
                          labelText: 'Senha',
                          suffixIcon: IconButton(
                            tooltip: hidden ? 'Mostrar senha' : 'Ocultar senha',
                            icon: Icon(
                              hidden ? Icons.visibility : Icons.visibility_off,
                            ),
                            onPressed: () => setState(() => hidden = !hidden),
                          ),
                        ),
                        validator: (value) =>
                            value == null || value.length < (signup ? 8 : 1)
                            ? (signup
                                  ? 'Use pelo menos oito caracteres'
                                  : 'Informe a senha')
                            : null,
                        onFieldSubmitted: (_) => submit(),
                      ),
                      if (message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(message!),
                        ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: busy ? null : submit,
                        child: Text(
                          busy
                              ? 'Aguarde…'
                              : signup
                              ? 'Cadastrar'
                              : 'Entrar',
                        ),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                signup = !signup;
                                message = null;
                              }),
                        child: Text(
                          signup ? 'Já tenho uma conta' : 'Criar conta',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class StoreGate extends StatefulWidget {
  const StoreGate({super.key});

  @override
  State<StoreGate> createState() => _StoreGateState();
}

class _StoreGateState extends State<StoreGate> {
  late Future<List<Store>> stores = load();
  Store? selected;

  Future<List<Store>> load() async {
    final rows = await db
        .from('members')
        .select('store_id, role, stores!inner(name)')
        .order('store_id');
    return rows.map(Store.new).toList();
  }

  Future<void> create() async {
    final name = await askText(context, 'Cadastrar loja', 'Nome da loja', 100);
    if (name == null || !mounted) return;
    setState(() => stores = createAndLoad(name));
  }

  Future<List<Store>> createAndLoad(String name) async {
    final id = await db.rpc<String>('create_store', params: {'p_name': name});
    final list = await load();
    if (mounted)
      setState(() => selected = list.firstWhere((store) => store.id == id));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (selected != null) {
      return Workspace(
        key: ValueKey(selected!.id),
        store: selected!,
        onSwitch: () {
          setState(() {
            selected = null;
            stores = load();
          });
        },
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text(title),
        actions: [
          TextButton(
            onPressed: () => signOut(context),
            child: const Text('Sair'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: FutureBuilder<List<Store>>(
            future: stores,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done)
                return const CircularProgressIndicator();
              if (snapshot.hasError)
                return Retry(
                  error: snapshot.error!,
                  onRetry: () => setState(() => stores = load()),
                );
              final list = snapshot.data!;
              return ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    'Minhas lojas',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  if (list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Cadastre sua loja ou peça à administração de uma loja para adicionar seu e-mail.',
                      ),
                    ),
                  for (final store in list)
                    ListTile(
                      leading: const Icon(Icons.storefront),
                      title: Text(store.name),
                      subtitle: Text(
                        store.isAdmin ? 'Administração' : 'Operação',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => setState(() => selected = store),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: create,
                    icon: const Icon(Icons.add),
                    label: const Text('Cadastrar loja'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => stores = load()),
                    child: const Text('Atualizar lista'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

Future<void> signOut(BuildContext context) async {
  try {
    await db.auth.signOut();
  } catch (error) {
    if (context.mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorLabel(error))));
  }
}

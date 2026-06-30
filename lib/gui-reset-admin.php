<?php
/**
 * Reset Cipi GUI primary admin — invoked by lib/gui.sh (cipi gui reset-user).
 * Usage: php gui-reset-admin.php <payload.json> <laravel-root>
 */
$payload = json_decode(file_get_contents($argv[1] ?? ''), true);
$root = $argv[2] ?? '';

if (! is_array($payload) || $root === '' || ! is_file($root.'/artisan')) {
    fwrite(STDERR, "Invalid reset payload\n");
    exit(1);
}

require $root.'/vendor/autoload.php';
$app = require $root.'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$user = App\Models\User::query()->orderBy('id')->first();
if (! $user) {
    fwrite(STDERR, "No admin user found\n");
    exit(1);
}

$user->forceFill([
    'email' => $payload['email'] ?? $user->email,
    'name' => $payload['name'] ?? $user->name,
    'password' => Illuminate\Support\Facades\Hash::make($payload['password']),
    'two_factor_secret' => null,
    'two_factor_enabled' => false,
    'two_factor_confirmed_at' => null,
])->save();

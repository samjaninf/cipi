<?php

namespace CipiGui\Console\Commands;

use App\Models\User;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

class SeedGuiUser extends Command
{
    protected $signature = 'cipi:seed-gui-user
                            {--email= : Admin email address}
                            {--password= : Admin password (random if omitted)}
                            {--name= : Admin display name}
                            {--reset : Reset the primary admin (rewrite email/name/password, clear 2FA)}';

    protected $description = 'Create or reset the Cipi GUI admin user';

    public function handle(): int
    {
        if ($this->option('reset')) {
            return $this->resetPrimaryAdmin();
        }

        $email = $this->option('email') ?? config('cipi-gui.default_admin_email');
        $name = $this->option('name') ?? config('cipi-gui.default_admin_name');
        $password = $this->option('password') ?? Str::password(16);

        User::updateOrCreate(
            ['email' => $email],
            [
                'name' => $name,
                'password' => Hash::make($password),
            ],
        );

        $this->printCredentials($email, $password, false, $this->option('password') !== null);

        return self::SUCCESS;
    }

    private function resetPrimaryAdmin(): int
    {
        $user = User::query()->orderBy('id')->first();

        if (! $user) {
            $email = $this->option('email') ?? config('cipi-gui.default_admin_email');
            $name = $this->option('name') ?? config('cipi-gui.default_admin_name');
            $password = $this->option('password') ?? Str::password(16);

            User::create([
                'email' => $email,
                'name' => $name,
                'password' => Hash::make($password),
            ]);

            $this->printCredentials($email, $password, true, $this->option('password') !== null);

            return self::SUCCESS;
        }

        $email = $this->option('email') ?? $user->email;
        $name = $this->option('name') ?? $user->name;
        $password = $this->option('password') ?? Str::password(16);

        $user->forceFill([
            'email' => $email,
            'name' => $name,
            'password' => Hash::make($password),
            'two_factor_secret' => null,
            'two_factor_enabled' => false,
            'two_factor_confirmed_at' => null,
        ])->save();

        $this->printCredentials($email, $password, true, $this->option('password') !== null);

        return self::SUCCESS;
    }

    private function printCredentials(string $email, string $password, bool $reset, bool $passwordProvided = false): void
    {
        $this->info($reset ? 'Cipi GUI admin user reset.' : 'Cipi GUI admin user ready.');
        $this->line("  Email:    {$email}");
        if (! $passwordProvided) {
            $this->line("  Password: {$password}");
        }
        $this->newLine();

        if ($reset) {
            $this->comment('Two-factor authentication was disabled. Re-enable it from Settings after login.');
        } else {
            $this->comment('Store the password securely. Enable 2FA from Settings after first login.');
        }
    }
}

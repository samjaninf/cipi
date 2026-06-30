<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}" class="h-full">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>{{ $title ?? 'Sign in' }} — Cipi GUI</title>
    @include('cipi-gui::partials.favicon')
    <link rel="preconnect" href="https://fonts.bunny.net">
    <link href="https://fonts.bunny.net/css?family=inter:400,500,600,700" rel="stylesheet">
    @include('cipi-gui::partials.styles')
</head>
<body class="h-full bg-surface-950 text-surface-100 font-sans antialiased">
    <div class="flex min-h-full flex-col justify-center py-12 sm:px-6 lg:px-8">
        <div class="sm:mx-auto sm:w-full sm:max-w-md">
            <div class="flex justify-center">
                @include('cipi-gui::partials.logo', ['size' => 'lg'])
            </div>
            <h2 class="mt-6 text-center text-2xl font-semibold tracking-tight text-white">Cipi Control Panel</h2>
            <p class="mt-2 text-center text-sm text-surface-400">@yield('subtitle', 'Sign in to manage your servers')</p>
        </div>

        <div class="mt-8 sm:mx-auto sm:w-full sm:max-w-md">
            <div class="rounded-2xl border border-surface-800 bg-surface-900/80 px-6 py-8 shadow-xl backdrop-blur-sm">
                @yield('content')
            </div>
        </div>
    </div>
</body>
</html>

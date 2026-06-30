@php
    $logoClass = $class ?? match ($size ?? 'md') {
        'sm' => 'h-8 w-8',
        'lg' => 'h-14 w-14 shadow-lg shadow-brand-600/30',
        default => 'h-9 w-9',
    };
@endphp

<svg class="{{ $logoClass }}" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Cipi">
    <rect width="32" height="32" rx="8" fill="url(#cipi-logo-gradient)"/>
    <path d="M21.75 11.25a6.75 6.75 0 1 0 0 9.5" stroke="#fff" stroke-width="2.75" stroke-linecap="round"/>
    <circle cx="21.75" cy="16" r="1.75" fill="#60a5fa"/>
    <defs>
        <linearGradient id="cipi-logo-gradient" x1="6" y1="4" x2="26" y2="28" gradientUnits="userSpaceOnUse">
            <stop stop-color="#3b82f6"/>
            <stop offset="1" stop-color="#1d4ed8"/>
        </linearGradient>
    </defs>
</svg>

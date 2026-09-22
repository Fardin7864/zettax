export type PrimeVestClientOptions = {
  baseUrl: string;
  accessToken?: () => string | undefined;
};

export class PrimeVestApiClient {
  constructor(private readonly options: PrimeVestClientOptions) {}

  async getPublicConfig(): Promise<unknown> {
    const response = await fetch(`${this.options.baseUrl}/system/config`, {
      headers: this.headers(),
    });
    if (!response.ok)
      throw new Error(`Zettax API request failed with ${response.status}`);
    return response.json();
  }

  private headers(): HeadersInit {
    const token = this.options.accessToken?.();
    return token ? { Authorization: `Bearer ${token}` } : {};
  }
}

export type AccessTokenPayload = {
  sub: string;
  sid: string;
  typ: "access";
};

export type RefreshTokenPayload = {
  sub: string;
  sid: string;
  family: string;
  ver: number;
  typ: "refresh";
};

export type RequestMetadata = {
  ipAddress?: string | undefined;
  userAgent?: string | undefined;
};

export type AuthenticatedPrincipal = {
  userId: string;
  sessionId: string;
};

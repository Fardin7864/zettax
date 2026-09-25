import { Body, Controller, Logger, Post } from '@nestjs/common';
import { IsIn, IsString, MaxLength } from 'class-validator';

class SiteEventDto {
  @IsIn(['navbar_download_clicked', 'download_clicked'])
  event!: string;

  @IsIn(['navbar', 'hero', 'section', 'footer'])
  source!: string;

  @IsIn(['android', 'ios', 'desktop'])
  deviceType!: string;

  @IsString()
  @MaxLength(200)
  currentPath!: string;
}

@Controller('site-events')
export class SiteEventsController {
  private readonly logger = new Logger(SiteEventsController.name);

  @Post()
  record(@Body() event: SiteEventDto) {
    // Structured server log is the first-party analytics sink. No user data or IP.
    this.logger.log(JSON.stringify({
      event: event.event,
      source: event.source,
      deviceType: event.deviceType,
      currentPath: event.currentPath,
    }));
    return { recorded: true };
  }
}
